module Math.Topology.KnotTh.SurfaceLink.Construction
    ( fromLink
    , toLink
    , fromTangleAndStar
    ) where

import Data.Array.IArray ((!))
import Math.Combinatorics.ChordDiagram
import Math.Topology.KnotTh.Knotted
import Math.Topology.KnotTh.SurfaceLink
import Math.Topology.KnotTh.Tangle
import Math.Topology.KnotTh.Link


fromLink :: (CrossingType ct) => Link ct -> SurfaceLink ct
fromLink = implode . explode


toLink :: (CrossingType ct) => SurfaceLink ct -> Link ct
toLink sl | eulerChar sl == 2  = implode (explode sl)
          | otherwise          = error "toLink: euler char must be 2"


fromTangleAndStar :: (CrossingType ct) => ChordDiagram -> Tangle ct -> SurfaceLink ct
fromTangleAndStar cd tangle
    | p /= l     = error "fromTangleAndStar: size conflict"
    | otherwise  = fromTangleAndStar' changeLeg tangle
    where
        p = numberOfPoints cd
        l = numberOfLegs tangle
        a = chordOffsetArray cd

        changeLeg d =
            let i = legPlace d
                j = (i + a ! i) `mod` l
            in nthLeg tangle j


{-# INLINE fromTangleAndStar' #-}
fromTangleAndStar' :: (CrossingType ct) => (Dart Tangle ct -> Dart Tangle ct) -> Tangle ct -> SurfaceLink ct
fromTangleAndStar' withLeg tangle =
    let watch d | isDart d   = toPair d
                | otherwise  = watch $ opposite $ withLeg d
    in implode
        ( numberOfFreeLoops tangle + div (length $ filter (\ l -> opposite l == withLeg l) $ allLegs tangle) 2
        , map (\ c -> (map watch $ adjacentDarts c, crossingState c)) $ allCrossings tangle
        )