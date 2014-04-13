{-# LANGUAGE TypeFamilies, UnboxedTuples, RankNTypes #-}
module Math.Topology.KnotTh.EmbeddedLink.EmbeddedLink
    ( EmbeddedLink
    , EmbeddedLinkProjection
    , EmbeddedLinkProjectionVertex
    , EmbeddedLinkProjectionDart
    , EmbeddedLinkDiagram
    , EmbeddedLinkDiagramVertex
    , EmbeddedLinkDiagramDart

    , ModifyELinkM
    , modifyELink
    , emitCircle
    , maskC
    , modifyC
    , connectC
    , substituteC
    ) where

import Data.Function (fix)
import Data.Maybe (fromMaybe)
import Data.List (foldl', find)
import Data.Bits ((.&.), shiftL, shiftR, complement)
import qualified Data.Vector as V
import qualified Data.Vector.Mutable as MV
import qualified Data.Vector.Unboxed as UV
import qualified Data.Vector.Unboxed.Mutable as UMV
import qualified Data.Vector.Primitive as PV
import qualified Data.Vector.Primitive.Mutable as PMV
import Data.STRef (STRef, newSTRef, readSTRef, writeSTRef, modifySTRef')
import Control.Monad.ST (ST, runST)
import Control.Monad.Reader (ReaderT, runReaderT, ask, lift)
import Control.Monad (void, when, forM, forM_, foldM, foldM_, guard)
import Control.DeepSeq (NFData(..))
import Text.Printf
import qualified Math.Algebra.Group.D4 as D4
import qualified Math.Algebra.RotationDirection as R
import Math.Topology.KnotTh.Knotted
import Math.Topology.KnotTh.Crossings.Projection
import Math.Topology.KnotTh.Crossings.Diagram


data EmbeddedLink a =
    EmbeddedLink
        { loopsCount      :: {-# UNPACK #-} !Int
        , vertexCount     :: {-# UNPACK #-} !Int
        , involutionArray :: {-# UNPACK #-} !(PV.Vector Int)
        , crossingsArray  :: {-# UNPACK #-} !(V.Vector a)
        , faceSystem      :: FaceSystem
        }

data FaceSystem =
    FaceSystem
        { faceCount       :: {-# UNPACK #-} !Int
        , faceDataOffset  :: {-# UNPACK #-} !(PV.Vector Int)
        , faceCCWBrdDart  :: {-# UNPACK #-} !(PV.Vector Int)
        , faceLLookup     :: {-# UNPACK #-} !(PV.Vector Int)
        }


instance PlanarDiagram EmbeddedLink where
    numberOfVertices = vertexCount

    numberOfEdges l = PV.length (involutionArray l) `shiftR` 1

    numberOfDarts l = PV.length (involutionArray l)

    nthVertex k i | i < 1 || i > b  = error $ printf "nthVertex: index %i is out of bounds (1, %i)" i b
                  | otherwise       = Vertex k (i - 1)
        where
             b = numberOfVertices k

    nthDart k i | i < 0 || i >= b  = error $ printf "nthDart: index %i is out of bounds (0, %i)" i b
                | otherwise        = Dart k i
        where
            b = PV.length (involutionArray k)

    allVertices k = map (Vertex k) [0 .. numberOfVertices k - 1]

    allHalfEdges k = map (Dart k) [0 .. PV.length (involutionArray k) - 1]

    allEdges k =
        foldl' (\ !es !i ->
                let j = involutionArray k `PV.unsafeIndex` i
                in if i < j
                    then (Dart k i, Dart k j) : es
                    else es
            ) [] [0 .. PV.length (involutionArray k) - 1]

    data Vertex EmbeddedLink a = Vertex !(EmbeddedLink a) {-# UNPACK #-} !Int

    vertexDegree _ = 4
    vertexOwner (Vertex k _) = k
    vertexIndex (Vertex _ i) = i + 1

    nthOutcomingDart (Vertex k c) i = Dart k ((c `shiftL` 2) + (i .&. 3))

    outcomingDarts c = map (nthOutcomingDart c) [0 .. 3]

    data Dart EmbeddedLink a = Dart !(EmbeddedLink a) {-# UNPACK #-} !Int

    dartOwner (Dart k _) = k
    dartIndex (Dart _ i) = i

    opposite (Dart k d) = Dart k (involutionArray k `PV.unsafeIndex` d)

    beginVertex (Dart k d) = Vertex k (d `shiftR` 2)

    beginPlace (Dart _ d) = d .&. 3

    nextCCW (Dart k d) = Dart k ((d .&. complement 3) + ((d + 1) .&. 3))

    nextCW (Dart k d) = Dart k ((d .&. complement 3) + ((d - 1) .&. 3))

    isDart _ = True

    vertexIndicesRange k = (1, numberOfVertices k)

    dartIndicesRange k = (0, numberOfDarts k - 1) 


instance (NFData a) => NFData (EmbeddedLink a) where
    rnf k = rnf (crossingsArray k) `seq` k `seq` ()

instance (NFData a) => NFData (Vertex EmbeddedLink a)

instance (NFData a) => NFData (Dart EmbeddedLink a)


instance Functor EmbeddedLink where
    fmap f k = k { crossingsArray = f `fmap` crossingsArray k }


instance Knotted EmbeddedLink where
    vertexCrossing (Vertex k i) = crossingsArray k `V.unsafeIndex` i

    mapCrossings f t =
        t { crossingsArray =
                V.generate (numberOfVertices t) $ \ i -> f (nthVertex t $ i + 1)
          }

    unrootedHomeomorphismInvariant link = UV.singleton (numberOfFreeLoops link) UV.++ internal
        where
            internal | numberOfVertices link == 0  = UV.empty
                     | otherwise                   = minimum $ do
                dart <- allHalfEdges link
                dir <- R.bothDirections
                globalG <- fromMaybe [D4.i] $ globalTransformations link
                return $! codeWithDirection globalG dir dart

            codeWithDirection !globalG !dir !start = UV.create $ do
                let n = numberOfVertices link

                index <- UMV.replicate (n + 1) 0
                incoming <- UMV.replicate (n + 1) 0
                queue <- MV.new n
                free <- newSTRef 1

                let {-# INLINE look #-}
                    look !d = do
                        let u = beginVertexIndex d
                        ux <- UMV.unsafeRead index u
                        if ux > 0
                            then do
                                up <- UMV.unsafeRead incoming u
                                return $! (ux `shiftL` 2) + (((beginPlace d - up) * R.directionSign dir) .&. 3)
                            else do
                                nf <- readSTRef free
                                writeSTRef free $! nf + 1
                                UMV.unsafeWrite index u nf
                                UMV.unsafeWrite incoming u (beginPlace d)
                                MV.unsafeWrite queue (nf - 1) d
                                return $! nf `shiftL` 2

                rc <- UMV.replicate (6 * n + 1) 0
                UMV.unsafeWrite rc 0 $! numberOfFreeLoops link

                let {-# INLINE lookAndWrite #-}
                    lookAndWrite !d !offset = do
                        look d >>= UMV.unsafeWrite rc offset
                        return $! offset + 1

                void $ look start
                flip fix 0 $ \ bfs !headI -> do
                            tailI <- readSTRef free
                            when (headI < tailI - 1) $ do
                                input <- MV.unsafeRead queue headI
                                void $ foldMAdjacentDartsFrom input dir lookAndWrite (6 * headI + 3)
                                case crossingCodeWithGlobal globalG dir input of
                                    (# be, le #) -> do
                                        UMV.unsafeWrite rc (6 * headI + 1) be
                                        UMV.unsafeWrite rc (6 * headI + 2) le
                                bfs $! headI + 1

                fix $ \ _ -> do
                    tailI <- readSTRef free
                    when (tailI <= n) $
                        fail "codeWithDirection: disconnected diagram (not implemented)"

                return rc

    isConnected link =
        numberOfFreeLoops link < (if numberOfVertices link == 0 then 2 else 1)

    type ExplodeType EmbeddedLink a = (Int, [([(Int, Int)], a)])

    explode link =
        ( numberOfFreeLoops link
        , map (\ v -> (map endPair' $ outcomingDarts v, vertexCrossing v)) $ allVertices link
        )

    implode (loops, list) = runST $ do
        when (loops < 0) $
            error $ printf "EmbeddedLink.implode: number of free loops %i is negative" loops

        let n = length list
        cr <- PMV.new (4 * n)
        st <- MV.new n

        forM_ (list `zip` [0 ..]) $ \ ((!ns, !cs), !i) -> do
            MV.unsafeWrite st i cs
            case ns of
                [p0, p1, p2, p3] ->
                    forM_ [(p0, 0), (p1, 1), (p2, 2), (p3, 3)] $ \ ((!c, !p), !j) -> do
                        let a = 4 * i + j
                            b | c < 1 || c > n  = error $ printf "EmbeddedLink.implode: crossing index %i is out of bounds [1 .. %i]" c n
                              | p < 0 || p > 3  = error $ printf "EmbeddedLink.implode: place index %i is out of bounds [0 .. 3]" p
                              | otherwise       = 4 * (c - 1) + p
                        when (a == b) $
                            error $ printf "EmbeddedLink.implode: (%i, %i) connected to itself" c p
                        PMV.unsafeWrite cr a b
                        when (b < a) $ do
                            x <- PMV.unsafeRead cr b
                            when (x /= a) $
                                error $ printf "EmbeddedLink.implode: (%i, %i) points to unconsistent position" c p

                _                ->
                    error $ printf "EmbeddedLink.implode: there must be 4 neighbours for every crossing, but found %i for %i-th"
                                        (length ns) (i + 1)

        cr' <- PV.unsafeFreeze cr
        st' <- V.unsafeFreeze st

        let link = EmbeddedLink
                { loopsCount      = loops
                , vertexCount     = n
                , involutionArray = cr'
                , crossingsArray  = st'
                , faceSystem      = makeFaceSystem link
                }

        return $! link


makeFaceSystem :: EmbeddedLink a -> FaceSystem
makeFaceSystem link =
    let n = numberOfVertices link

        (fcN, fllookN, fccwdN) = runST $ do
            fccwd <- PMV.new (4 * n)
            fllook <- PMV.replicate (8 * n) (-1)

            (fc, _) <- foldM (\ (!fid, !base) !start -> do
                mi <- PMV.read fllook (2 * start)
                if mi >= 0
                    then return (fid, base)
                    else do
                        sz <- fix (\ mark !offset !i -> do
                            PMV.write fllook (2 * i) fid
                            PMV.write fllook (2 * i + 1) offset
                            PMV.write fccwd (base + offset) i

                            let i' = involutionArray link `PV.unsafeIndex` i
                                j = (i' .&. complement 3) + ((i' - 1) .&. 3)
                            mj <- PMV.read fllook (2 * j)
                            if mj >= 0
                                then return $! offset + 1
                                else mark (offset + 1) j
                            ) 0 start
                        return (fid + 1, base + sz)
                ) (0, 0) [0 .. 4 * n - 1]

            fccwd' <- PV.unsafeFreeze fccwd
            fllook' <- PV.unsafeFreeze fllook
            return (fc, fllook', fccwd')

        foffN = PV.create $ do
            foff <- PMV.replicate (fcN + 1) 0
            forM_ [0 .. 4 * n - 1] $ \ !i -> do
                let fid = fllookN PV.! (2 * i)
                cur <- PMV.read foff fid
                PMV.write foff fid $! cur + 1
            foldM_ (\ !offset !i -> do
                    cur <- PMV.read foff i
                    PMV.write foff i offset
                    return $! offset + cur
                ) 0 [0 .. fcN]
            return foff

    in FaceSystem
            { faceCount       = fcN
            , faceDataOffset  = foffN
            , faceCCWBrdDart  = fccwdN
            , faceLLookup     = fllookN
            }


instance KnottedPlanar EmbeddedLink where
    numberOfFreeLoops = loopsCount

    changeNumberOfFreeLoops loops k | loops >= 0  = k { loopsCount = loops }
                                    | otherwise   = error $ printf "changeNumberOfFreeLoops: number of free loops %i is negative" loops 

    emptyKnotted =
        EmbeddedLink
            { loopsCount      = 0
            , vertexCount     = 0
            , involutionArray = PV.empty
            , crossingsArray  = V.empty
            , faceSystem      =
                FaceSystem
                    { faceCount       = 1
                    , faceDataOffset  = PV.replicate 2 0
                    , faceCCWBrdDart  = PV.empty
                    , faceLLookup     = PV.empty
                    }
            }


instance KnottedDiagram EmbeddedLink where
    isReidemeisterReducible =
        any (\ ab ->
                let ba = opposite ab
                    ac = nextCCW ab
                in (ac == ba) || (passOver ab == passOver ba && opposite ac == nextCW ba)
            ) . allOutcomingDarts

    tryReduceReidemeisterI link = do
        d <- find (\ d -> opposite d == nextCCW d) (allOutcomingDarts link)
        return $! modifyELink link $ do
            let ac = nextCW d
                ab = nextCW ac
                ba = opposite ab
            substituteC [(ba, ac)]
            maskC [beginVertex d]

    tryReduceReidemeisterII link = do
        abl <- find (\ abl ->
                let bal = opposite abl
                    abr = nextCCW abl
                    bar = nextCW bal
                in passOver abl == passOver bal
                    && abr == opposite bar
                    && beginVertex abl /= beginVertex bal
            ) (allOutcomingDarts link)

        let bal = opposite abl
            a = beginVertex abl
            b = beginVertex bal

            ap = threadContinuation abl
            aq = nextCW abl
            br = nextCCW bal
            bs = threadContinuation bal

            pa = opposite ap
            qa = opposite aq
            rb = opposite br
            sb = opposite bs

        return $! if rightFace (nextCW abl) == leftFace (nextCCW bal)
            then emptyKnotted
            else modifyELink link $ do
                case () of
                    _ | qa == ap || rb == bs ->
                        if qa == ap && rb == bs
                            then emitCircle 1
                            else connectC $ [(pa, qa) | qa /= ap] ++ [(rb, sb) | rb /= bs]

                      | qa == bs || rb == ap ->
                        if qa == bs && rb == ap
                            then error "strange configuration"
                            else connectC $ [(sb, qa) | qa /= bs] ++ [(rb, pa) | rb /= ap]

                      | otherwise            -> do
                        if qa == br
                            then emitCircle 1
                            else connectC [(qa, rb)]
                        if pa == bs
                            then emitCircle 1
                            else connectC [(pa, sb)]

                maskC [a, b]

    reidemeisterIII link = do
        ab <- allOutcomingDarts link
        let ac = nextCCW ab
            ba = opposite ab
            ca = opposite ac
            bc = nextCW ba
            cb = nextCCW ca

        guard $ bc == opposite cb

        let a = beginVertex ab
            b = beginVertex ba
            c = beginVertex ca

        guard $ (a /= b) && (a /= c) && (b /= c)
        guard $ passOver bc == passOver cb

        guard $ let altRoot | passOver ab == passOver ba  = ca
                            | otherwise                   = bc
                in ab < altRoot

        let ap = threadContinuation ab
            aq = nextCW ab
            br = nextCW bc
            cs = nextCCW cb

        return $! modifyELink link $ do
            substituteC [(ca, ap), (ba, aq), (ab, br), (ac, cs)]
            connectC [(br, aq), (cs, ap)]


instance (Show a) => Show (EmbeddedLink a) where
    show = printf "implode %s" . show . explode


instance (Show a) => Show (Vertex EmbeddedLink a) where
    show v =
        printf "(Crossing %i %s [ %s ])"
            (vertexIndex v)
            (show $ vertexCrossing v)
            (unwords $ map (show . opposite) $ outcomingDarts v)


instance Show (Dart EmbeddedLink a) where
    show d = let (c, p) = beginPair' d
             in printf "(Dart %i %i)" c p


instance SurfaceDiagram EmbeddedLink where
    numberOfFaces = faceCount . faceSystem

    nthFace link i | i > 0 && i <= n  = Face link (i - 1)
                   | otherwise        = error $ printf "nthFace: index %i is out of bounds (1, %i)" i n
        where
            n = numberOfFaces link

    allFaces link = map (Face link) [1 .. numberOfFaces link]

    data Face EmbeddedLink ct = Face !(EmbeddedLink ct) {-# UNPACK #-} !Int

    faceDegree (Face l i) =
        let cur = faceDataOffset (faceSystem l) `PV.unsafeIndex` i
            nxt = faceDataOffset (faceSystem l) `PV.unsafeIndex` (i + 1)
        in nxt - cur

    faceOwner (Face l _) = l

    faceIndex (Face _ i) = i + 1

    leftFace (Dart l i) = Face l $ faceLLookup (faceSystem l) `PV.unsafeIndex` (2 * i)

    leftPlace (Dart l i) = faceLLookup (faceSystem l) `PV.unsafeIndex` (2 * i + 1)

    nthDartInCCWTraverse (Face l i) p =
        let cur = faceDataOffset (faceSystem l) `PV.unsafeIndex` i
            nxt = faceDataOffset (faceSystem l) `PV.unsafeIndex` (i + 1)
        in Dart l $ faceCCWBrdDart (faceSystem l) `PV.unsafeIndex` (cur + p `mod` (nxt - cur))

    faceIndicesRange l = (1, numberOfFaces l)


instance SurfaceKnotted EmbeddedLink


type EmbeddedLinkProjection = EmbeddedLink ProjectionCrossing
type EmbeddedLinkProjectionVertex = Vertex EmbeddedLink ProjectionCrossing
type EmbeddedLinkProjectionDart = Dart EmbeddedLink ProjectionCrossing


type EmbeddedLinkDiagram = EmbeddedLink DiagramCrossing
type EmbeddedLinkDiagramVertex = Vertex EmbeddedLink DiagramCrossing
type EmbeddedLinkDiagramDart = Dart EmbeddedLink DiagramCrossing



type ModifyELinkM a s r = ReaderT (ModifyState a s) (ST s) r


data CrossingMask = Direct | Flipped | Masked deriving (Show)

data ModifyState a s =
    ModifyState
        { stateSource     :: !(EmbeddedLink a)
        , stateCircles    :: !(STRef s Int)
        , stateInvolution :: !(PMV.STVector s Int)
        , stateMask       :: !(MV.STVector s CrossingMask)
        }


modifyELink :: (Show a) => EmbeddedLink a -> (forall s. ModifyELinkM a s ()) -> EmbeddedLink a
modifyELink link action = runST $ do
    s <- disassembleST link
    runReaderT action s
    assembleST s


disassembleST :: EmbeddedLink a -> ST s (ModifyState a s)
disassembleST link = do
    circ <- newSTRef $ numberOfFreeLoops link
    inv <- PV.thaw $ involutionArray link
    mask <- MV.replicate (numberOfVertices link) Direct
    return $! ModifyState
                  { stateSource     = link
                  , stateCircles    = circ
                  , stateInvolution = inv
                  , stateMask       = mask
                  }


assembleST :: (Show a) => ModifyState a s -> ST s (EmbeddedLink a)
assembleST s = do
    let src = stateSource s
    mask <- V.freeze $ stateMask s
    let crs = V.ifilter (\ !i _ -> case mask V.! i of Masked -> False ; _ -> True) $ crossingsArray src
        n = V.length crs
        idx = UV.fromList $ do
            let offsets = UV.prescanl'
                              (\ off i -> off + case mask V.! i of Masked -> 0 ; _ -> 1)
                              0
                              (UV.enumFromN 0 $ vertexCount src)
            i <- [0 .. vertexCount src - 1]
            let d = 4 * (offsets UV.! i)
            case mask V.! i of
                Masked  -> [-1, -1, -1, -1]
                Direct  -> [d, d + 1, d + 2, d + 3]
                Flipped -> [d + 3, d + 2, d + 1, d]

    inv <- PV.freeze $ stateInvolution s
    forM_ [0 .. vertexCount src - 1] $ \ !v ->
        case mask V.! v of
            Masked -> return ()
            _      ->
                forM_ [0 .. 3] $ \ !i ->
                    let a = 4 * v + i
                        b = inv PV.! a
                    in case mask V.! (b `shiftR` 2) of
                        Masked -> fail $ printf "modifyELink: touching masked crossing\nlink: %s\nmask: %s\ninvolution: %s"
                               (show src) (show mask) (show inv)
                        _      -> return ()

    loops <- readSTRef $ stateCircles s
    let link = EmbeddedLink
            { loopsCount      = loops
            , vertexCount     = n
            , involutionArray =
                PV.map (idx UV.!) $ PV.concat $ do
                    i <- [0 .. vertexCount src - 1]
                    return $! case mask V.! i of
                        Masked  -> PV.empty
                        Direct  -> PV.slice (4 * i) 4 inv
                        Flipped -> PV.reverse $ PV.slice (4 * i) 4 inv
            , crossingsArray  = crs
            , faceSystem      = makeFaceSystem link
            }
    return link


emitCircle :: Int -> ModifyELinkM a s ()
emitCircle dn =
    ask >>= \ !s -> lift $
        modifySTRef' (stateCircles s) (+ dn)


maskC :: [Vertex EmbeddedLink a] -> ModifyELinkM a s ()
maskC crossings =
    ask >>= \ !s -> lift $
        forM_ crossings $ \ (Vertex _ i) ->
            MV.write (stateMask s) i Masked


modifyC :: (Show a) => Bool -> [Vertex EmbeddedLink a] -> ModifyELinkM a s ()
modifyC needFlip crossings =
    ask >>= \ !s -> lift $
        forM_ crossings $ \ (Vertex _ c) -> do
            msk <- MV.read (stateMask s) c
            MV.write (stateMask s) c $
                case msk of
                    Direct  | needFlip  -> Flipped
                            | otherwise -> Direct
                    Flipped | needFlip  -> Direct
                            | otherwise -> Flipped
                    Masked              -> error $ printf "modifyC: flipping masked crossing %s" (show c)


connectC :: [(Dart EmbeddedLink a, Dart EmbeddedLink a)] -> ModifyELinkM a s ()
connectC connections =
    ask >>= \ !s -> lift $
        forM_ connections $ \ (Dart _ !a, Dart _ !b) -> do
            when (a == b) $ fail $ printf "reconnect: %s connect to itself" (show a)
            PMV.write (stateInvolution s) a b
            PMV.write (stateInvolution s) b a


substituteC :: [(Dart EmbeddedLink a, Dart EmbeddedLink a)] -> ModifyELinkM a s ()
substituteC substitutions = do
    reconnections <- mapM (\ (a, b) -> (,) a `fmap` oppositeC b) substitutions
    st <- ask
    x <- lift $ do
        let source = stateSource st

        arr <- MV.new (numberOfDarts source)
        forM_ (allEdges source) $ \ (!a, !b) -> do
            MV.write arr (dartIndex a) a
            MV.write arr (dartIndex b) b

        forM_ substitutions $ \ (a, b) ->
            if a == b
                then modifySTRef' (stateCircles st) (+ 1)
                else MV.write arr (dartIndex b) a

        forM reconnections $ \ (a, b) ->
            (,) a `fmap` MV.read arr (dartIndex b)

    connectC x


oppositeC :: Dart EmbeddedLink a -> ModifyELinkM a s (Dart EmbeddedLink a)
oppositeC (Dart link d) =
    ask >>= \ !s -> lift $
        Dart link `fmap` PMV.read (stateInvolution s) d