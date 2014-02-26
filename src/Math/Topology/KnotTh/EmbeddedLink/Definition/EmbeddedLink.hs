{-# LANGUAGE TemplateHaskell, TypeFamilies, UnboxedTuples #-}
module Math.Topology.KnotTh.EmbeddedLink.Definition.EmbeddedLink
    ( EmbeddedLink
    , EmbeddedLinkProjection
    , EmbeddedLinkProjectionVertex
    , EmbeddedLinkProjectionDart
    , EmbeddedLinkDiagram
    , EmbeddedLinkDiagramVertex
    , EmbeddedLinkDiagramDart
    ) where

import Language.Haskell.TH
import Data.Function (fix)
import Data.Maybe (fromMaybe)
import Data.Bits ((.&.), shiftL, complement)
import qualified Data.Vector.Mutable as MV
import qualified Data.Vector.Primitive as PV
import qualified Data.Vector.Primitive.Mutable as PMV
import Data.STRef (newSTRef, readSTRef, writeSTRef)
import Control.Monad.ST (ST)
import Control.Monad (void, when, forM_, foldM, foldM_)
import Text.Printf
import qualified Math.Algebra.Group.D4 as D4
import qualified Math.Algebra.RotationDirection as R
import Math.Topology.KnotTh.Knotted
import Math.Topology.KnotTh.Crossings.Projection
import Math.Topology.KnotTh.Crossings.Diagram
import Math.Topology.KnotTh.Knotted.TH.Knotted


produceKnotted
    [d| data EmbeddedLink ct =
            EmbeddedLink
                { faceCount      :: {-# UNPACK #-} !Int
                , faceDataOffset :: {-# UNPACK #-} !(PV.Vector Int)
                , faceCCWBrdDart :: {-# UNPACK #-} !(PV.Vector Int)
                , faceLLookup    :: {-# UNPACK #-} !(PV.Vector Int)
                }

        instance Knotted EmbeddedLink where
            vertexCrossing = undefined
            numberOfFreeLoops = undefined
            changeNumberOfFreeLoops = undefined
            emptyKnotted = undefined

            type ExplodeType EmbeddedLink a = (Int, [([(Int, Int)], a)])

            implode = undefined

            explode link =
                ( numberOfFreeLoops link
                , map (\ v -> (map endPair' $ outcomingDarts v, vertexCrossing v)) $ allVertices link
                )

            homeomorphismInvariant link =
                minimum $ do
                    dart <- allHalfEdges link
                    dir <- R.bothDirections
                    globalG <- fromMaybe [D4.i] $ globalTransformations link
                    return $! codeWithDirection globalG dir dart

                where
                    codeWithDirection !globalG !dir !start = PV.create $ do
                        let n = numberOfVertices link

                        index <- PMV.replicate (n + 1) 0
                        incoming <- PMV.replicate (n + 1) 0
                        queue <- MV.new n
                        free <- newSTRef 1

                        let {-# INLINE look #-}
                            look !d = do
                                let u = beginVertexIndex d
                                ux <- PMV.unsafeRead index u
                                if ux > 0
                                    then do
                                        up <- PMV.unsafeRead incoming u
                                        return $! (ux `shiftL` 2) + (((beginPlace d - up) * R.directionSign dir) .&. 3)
                                    else do
                                        nf <- readSTRef free
                                        writeSTRef free $! nf + 1
                                        PMV.unsafeWrite index u nf
                                        PMV.unsafeWrite incoming u (beginPlace d)
                                        MV.unsafeWrite queue (nf - 1) d
                                        return $! nf `shiftL` 2

                        rc <- PMV.replicate (6 * n + 1) 0
                        PMV.unsafeWrite rc 0 $! numberOfFreeLoops link

                        let {-# INLINE lookAndWrite #-}
                            lookAndWrite !d !offset = do
                                look d >>= PMV.unsafeWrite rc offset
                                return $! offset + 1

                        void $ look start
                        flip fix 0 $ \ bfs !headI -> do
                            tailI <- readSTRef free
                            when (headI < tailI - 1) $ do
                                input <- MV.unsafeRead queue headI
                                void $ foldMAdjacentDartsFrom input dir lookAndWrite (6 * headI + 3)
                                case crossingCodeWithGlobal globalG dir input of
                                    (# be, le #) -> do
                                        PMV.unsafeWrite rc (6 * headI + 1) be
                                        PMV.unsafeWrite rc (6 * headI + 2) le
                                bfs $! headI + 1

                        fix $ \ _ -> do
                            tailI <- readSTRef free
                            when (tailI <= n) $
                                fail "codeWithDirection: disconnected diagram (not implemented)"

                        return rc

            isConnected _ = error "isConnected: not implemented"

    |] $
    let fcN = mkName "fc"
        fllookN = mkName "fllook"
        foffN = mkName "foff"
        fccwdN = mkName "fccwd"
    in defaultKnotted
        { implodeExplodeSettings = defaultImplodeExplode
            { implodePostExtra = \ n cr spliceFill -> (:[]) $
                bindS (tupP [varP fcN, varP fllookN, varP foffN, varP fccwdN]) [| do
                    fccwd <- PMV.new (4 * $n) :: ST s (PMV.STVector s Int)
                    fllook <- PMV.replicate (8 * $n) (-1) :: ST s (PMV.STVector s Int)

                    (fc, _) <- foldM (\ (!fid, !base) !start -> do
                        mi <- PMV.read fllook (2 * start)
                        if mi >= 0
                            then return (fid, base)
                            else do
                                sz <- fix (\ mark !offset !i -> do
                                    PMV.write fllook (2 * i) fid
                                    PMV.write fllook (2 * i + 1) offset
                                    PMV.write fccwd (base + offset) i

                                    i' <- PMV.unsafeRead $cr i
                                    let j = (i' .&. complement 3) + ((i' - 1) .&. 3)
                                    mj <- PMV.read fllook (2 * j)
                                    if mj >= 0
                                        then return $! offset + 1
                                        else mark (offset + 1) j
                                    ) 0 start
                                return (fid + 1, base + sz)
                        ) (0, 0) [0 .. 4 * $n - 1]

                    foff <- PMV.replicate (fc + 1) 0 :: ST s (PMV.STVector s Int)
                    forM_ [0 .. 4 * $n - 1] $ \ !i -> do
                        fid <- PMV.read fllook (2 * i)
                        cur <- PMV.read foff fid
                        PMV.write foff fid $! cur + 1
                    foldM_ (\ !offset !i -> do
                            cur <- PMV.read foff i
                            PMV.write foff i offset
                            return $! offset + cur
                        ) 0 [0 .. fc]

                    fccwd' <- PV.unsafeFreeze fccwd
                    fllook' <- PV.unsafeFreeze fllook
                    foff' <- PV.unsafeFreeze foff
                    return (fc, fllook', foff', fccwd')
                    |]

            , implodeInitializers =
                [ (,) (mkName "faceCount")      `fmap` varE fcN
                , (,) (mkName "faceDataOffset") `fmap` varE foffN
                , (,) (mkName "faceCCWBrdDart") `fmap` varE fccwdN
                , (,) (mkName "faceLLookup")    `fmap` varE fllookN
                ]
            }

        , emptyExtraInitializers =
            [ (,) (mkName "faceCount")      `fmap` [| 1 :: Int |]
            , (,) (mkName "faceDataOffset") `fmap` [| PV.replicate 2 0 |]
            , (,) (mkName "faceCCWBrdDart") `fmap` [| PV.empty |]
            , (,) (mkName "faceLLookup")    `fmap` [| PV.empty |]
            ]
        }


instance Show (Dart EmbeddedLink a) where
    show d = let (c, p) = beginPair' d
             in printf "(Dart %i %i)" c p


instance SurfaceDiagram EmbeddedLink where
    numberOfFaces = faceCount

    nthFace link i | i > 0 && i <= n  = Face link (i - 1)
                   | otherwise        = error $ printf "nthFace: index %i is out of bounds (1, %i)" i n
        where
            n = numberOfFaces link

    allFaces link = map (Face link) [1 .. numberOfFaces link]

    data Face EmbeddedLink ct = Face !(EmbeddedLink ct) {-# UNPACK #-} !Int

    faceDegree (Face l i) =
        let cur = faceDataOffset l `PV.unsafeIndex` i
            nxt = faceDataOffset l `PV.unsafeIndex` (i + 1)
        in nxt - cur

    faceOwner (Face l _) = l

    faceIndex (Face _ i) = i + 1

    leftFace (Dart l i) = Face l $ faceLLookup l `PV.unsafeIndex` (2 * i)

    leftPlace (Dart l i) = faceLLookup l `PV.unsafeIndex` (2 * i + 1)

    nthDartInCCWTraverse (Face l i) p =
        let cur = faceDataOffset l `PV.unsafeIndex` i
            nxt = faceDataOffset l `PV.unsafeIndex` (i + 1)
        in Dart l $ faceCCWBrdDart l `PV.unsafeIndex` (cur + p `mod` (nxt - cur))

    faceIndicesRange l = (1, numberOfFaces l)


instance SurfaceKnotted EmbeddedLink


type EmbeddedLinkProjection = EmbeddedLink ProjectionCrossing
type EmbeddedLinkProjectionVertex = Vertex EmbeddedLink ProjectionCrossing
type EmbeddedLinkProjectionDart = Dart EmbeddedLink ProjectionCrossing


type EmbeddedLinkDiagram = EmbeddedLink DiagramCrossing
type EmbeddedLinkDiagramVertex = Vertex EmbeddedLink DiagramCrossing
type EmbeddedLinkDiagramDart = Dart EmbeddedLink DiagramCrossing
