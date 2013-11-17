module Math.Topology.KnotTh.SurfaceLink.Definition.EdgeIndicesEncoding
    ( encodeEdgeIndices
    ) where

import Data.List (sort)
import Math.Topology.KnotTh.Knotted
import Math.Topology.KnotTh.Crossings.Projection
import Math.Topology.KnotTh.Crossings.Arbitrary
import Math.Topology.KnotTh.SurfaceLink.Definition.SurfaceLink


class (CrossingType ct) => EdgeIndicesCrossing ct where
    indexPlace :: Dart SurfaceLink ct -> Int


instance EdgeIndicesCrossing ProjectionCrossing where
    indexPlace = beginPlace


instance EdgeIndicesCrossing ArbitraryCrossing where
    indexPlace d | passOver (nthOutcomingDart c 0)  = p
                 | otherwise                        = (p - 1) `mod` 4
        where
            (c, p) = beginPair d


encodeEdgeIndices :: (EdgeIndicesCrossing ct) => SurfaceLink ct -> [Int]
encodeEdgeIndices link =
    let offset d =
            let c = beginVertex d
            in 4 * (vertexIndex c - 1) + indexPlace d
    in map snd $ sort $ do
        (i, (a, b)) <- [1 ..] `zip` allEdges link
        [(offset a, i), (offset b, i)]
