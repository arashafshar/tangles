module Math.Topology.KnotTh.Tangle.Generation.FlypeClasses
    ( generateFlypeEquivalentDecomposition
    , generateFlypeEquivalentDecompositionInTriangle
    , generateFlypeEquivalent
    , generateFlypeEquivalentInTriangle
    ) where

import Data.List (nubBy, partition)
import Data.Array ((!), (//), listArray)
import Data.Function (fix)
import Control.Monad.State.Strict (evalStateT, execStateT, get, put, lift)
import Control.Arrow (first)
import Control.Monad (forM_, when)
import qualified Math.Algebra.RotationDirection as R
import qualified Math.Algebra.Group.Dn as Dn
import Math.Topology.KnotTh.Crossings.SubTangle
import Math.Topology.KnotTh.Tangle
import Math.Topology.KnotTh.Tangle.Generation.BorderIncremental.IncrementalGluing
import Math.Topology.KnotTh.Tangle.Generation.BorderIncremental.RootingTest (rootCodeLeg, minimumRootCode)
import Math.Topology.KnotTh.Tangle.Generation.BorderIncremental.IncrementalTests
import Math.Topology.KnotTh.Tangle.Generation.FlypeClasses.Flypes


generateFlypeEquivalentDecomposition' :: (Monad m) => Bool -> Int -> ((SubTangleTangle ProjectionCrossing, Dn.DnSubGroup) -> m ()) -> m ()
generateFlypeEquivalentDecomposition' triangle maxN yield = do

    let templateType = GluingType
            { preGlueTest  = \ _ leg gl ->
                let t = dartOwner leg
                in case () of
                    _ | numberOfVertices t == 1 -> gl < 2
                      | numberOfLegs t == 4     -> False
                      | otherwise               -> testNoMultiEdges leg gl
            , postGlueTest = \ root gl _ s ->
                if gl < 3 || testFlow4 root
                    then return $! s
                    else Nothing
            }

    let directSumType = GluingType
            { preGlueTest  = \ cr leg gl ->
                let t = dartOwner leg
                    lp = directSumDecompositionType cr
                    rp = directSumDecompositionTypeInside (opposite leg)
                in case () of
                    _ | numberOfLegs t /= 4     -> False
                      | gl /= 2                 -> False
                      | testNoMultiEdges leg gl -> False
                      | lp == DirectSum01x23    -> False
                      | numberOfVertices t == 1 -> rp /= DirectSum12x30
                      | otherwise               -> True
            , postGlueTest = \ root _ leg s ->
                let coLeg = nextCCW $ nextCCW leg
                    flypeS =
                        case additionalFlypeSymmetry (vertexOwner root) of
                            Just x  -> Dn.addSymmetryToSubGroup s x
                            Nothing -> s
                in case (isLonerInside root, isLonerInside $ beginVertex $ opposite leg, isLonerInside $ beginVertex $ opposite coLeg) of
                    (False, False, False) -> return $! s
                    (True , True , _    ) -> return $! flypeS
                    (True , False, False) ->
                        if min (rootCodeLeg leg R.ccw) (rootCodeLeg (nextCW leg) R.cw) <= min (rootCodeLeg coLeg R.ccw) (rootCodeLeg (nextCW coLeg) R.cw)
                            then return $! flypeS
                            else Nothing
                    _                     -> Nothing
            }

    let directSumDescendants crossings ancestor =
            let (loners, nonLoners) = partition ((== 1) . numberOfVertices . subTangle) crossings
            in nubBy (\ (a, _) (b, _) -> minimumRootCode a == minimumRootCode b) (canonicalGluing directSumType $ allGluingSites' loners 2 $ fst ancestor)
                ++ canonicalGluing directSumType (representativeGluingSites' nonLoners 2 ancestor)

    let buildCrossingType template symmetry =
            let sumType
                    | (a == b) && (c == d) && (a /= c)  = DirectSum01x23
                    | (b == c) && (a == d) && (a /= b)  = DirectSum12x30
                    | otherwise                         = NonDirectSumDecomposable
                    where
                        [a, b, c, d] = map endVertex $ allLegs template
            in fromTangle' template symmetry sumType

    let halfN = maxN `div` 2

    (finalFree, finalCrossings, rootList) <- flip execStateT (0, listArray (1, halfN) $ repeat [], []) $
        let lonerSymmetry = Dn.maximumSubGroup 4
            loner = makeCrossing' $ fromTangle lonerProjection lonerSymmetry NonDirectSumDecomposable 0
        in flip fix (lonerTangle loner, lonerSymmetry) $ \ growTree (rootTemplate, rootSymmetry) -> do
            (!free, !prevCrossings, !prevList) <- get
            let rootCrossing = buildCrossingType rootTemplate rootSymmetry free
            let rootN = numberOfVertices $ subTangle rootCrossing
            let crossings = prevCrossings // [(rootN, rootCrossing : (prevCrossings ! rootN))]
            let root = lonerTangle $ makeCrossing' rootCrossing
            put (free + 1, crossings, ((root, rootSymmetry), crossings) : prevList)

            let glueTemplates curN ancestor@(ancestorTangle, _) =
                    forM_ [1 .. halfN - curN] $ \ cn -> do
                        let sites =
                                let half (gl, _, _) = diagonalIndex (curN + cn) (nextNumberOfLegs (numberOfLegs ancestorTangle) gl) <= halfN
                                in filter half $ representativeGluingSites (crossings ! cn) ancestor
                        forM_ (canonicalGluing templateType sites) $ \ child@(childTangle, _) ->
                            case numberOfLegs childTangle of
                                4 -> growTree child
                                _ -> glueTemplates (curN + cn) child

            let glueDirectSums curN ancestor =
                    forM_ [1 .. halfN - curN] $ \ cn ->
                        forM_ (directSumDescendants (crossings ! cn) ancestor) $ \ child -> do
                            growTree child
                            glueDirectSums (curN + cn) child

            lift $ yield (rootTemplate, rootSymmetry)
            glueTemplates rootN (root, rootSymmetry)
            glueDirectSums rootN (root, rootSymmetry)

    flip evalStateT finalFree $ forM_ rootList $ fix $ \ grow (root, crossings) -> do
        let tree curN (rootTemplate, rootSymmetry) =
                when (curN > halfN) $ do
                    free <- get
                    put $! free + 1
                    lift $ yield (rootTemplate, rootSymmetry)
                    grow ((lonerTangle $ makeCrossing' $ buildCrossingType rootTemplate rootSymmetry free, rootSymmetry), finalCrossings)

        let glueTemplates curN ancestor@(ancestorTangle, _) =
                forM_ [1 .. min halfN (maxN - curN)] $ \ cn -> do
                    let sites =
                            let inTriangle (gl, _, _)
                                    | triangle   = diagonalIndex (curN + cn) (nextNumberOfLegs (numberOfLegs ancestorTangle) gl) <= maxN
                                    | otherwise  = True
                            in filter inTriangle $ representativeGluingSites (crossings ! cn) ancestor
                    forM_ (canonicalGluing templateType sites) $ \ child@(childTangle, childSymmetry) ->
                        case numberOfLegs childTangle of
                            4 -> tree (curN + cn) child
                            _ -> lift (yield (childTangle, childSymmetry)) >> glueTemplates (curN + cn) child

        let glueDirectSums curN ancestor =
                forM_ [1 .. min halfN (maxN - curN)] $ \ cn ->
                    forM_ (directSumDescendants (crossings ! cn) ancestor) $ \ child -> do
                        tree (curN + cn) child
                        glueDirectSums (curN + cn) child

        let rootN = numberOfCrossingsAfterSubstitution $ fst root
        glueTemplates rootN root
        glueDirectSums rootN root


generateFlypeEquivalentDecomposition :: (Monad m) => Int -> ((SubTangleTangle ProjectionCrossing, Dn.DnSubGroup) -> m ()) -> m ()
generateFlypeEquivalentDecomposition =
    generateFlypeEquivalentDecomposition' False


generateFlypeEquivalentDecompositionInTriangle :: (Monad m) => Int -> ((SubTangleTangle ProjectionCrossing, Dn.DnSubGroup) -> m ()) -> m ()
generateFlypeEquivalentDecompositionInTriangle =
    generateFlypeEquivalentDecomposition' True


generateFlypeEquivalent :: (Monad m) => Int -> ((TangleProj, Dn.DnSubGroup) -> m ()) -> m ()
generateFlypeEquivalent maxN =
    generateFlypeEquivalentDecomposition maxN . (. first substituteTangle)


generateFlypeEquivalentInTriangle :: (Monad m) => Int -> ((TangleProj, Dn.DnSubGroup) -> m ()) -> m ()
generateFlypeEquivalentInTriangle maxN =
    generateFlypeEquivalentDecompositionInTriangle maxN . (. first substituteTangle)
