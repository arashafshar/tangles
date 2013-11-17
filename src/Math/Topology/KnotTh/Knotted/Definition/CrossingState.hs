module Math.Topology.KnotTh.Knotted.Definition.CrossingState
    ( crossingTypeInside
    , isCrossingOrientationInvertedInside
    , crossingLegIdByDart
    , dartByCrossingLegId
    , makeCrossing'
    ) where

import qualified Math.Algebra.Group.D4 as D4
import Math.Topology.KnotTh.Knotted.Definition.Knotted


{-# INLINE crossingTypeInside #-}
crossingTypeInside :: (CrossingType ct, Knotted k) => Vertex k ct -> ct
crossingTypeInside = crossingType . crossingState


{-# INLINE isCrossingOrientationInvertedInside #-}
isCrossingOrientationInvertedInside :: (CrossingType ct, Knotted k) => Vertex k ct -> Bool
isCrossingOrientationInvertedInside = isCrossingOrientationInverted . crossingState


{-# INLINE crossingLegIdByDart #-}
crossingLegIdByDart :: (CrossingType ct, Knotted k) => Dart k ct -> Int
crossingLegIdByDart d = crossingLegIdByDartId (crossingState $ beginVertex d) (beginPlace d)


{-# INLINE dartByCrossingLegId #-}
dartByCrossingLegId :: (CrossingType ct, Knotted k) => Vertex k ct -> Int -> Dart k ct
dartByCrossingLegId c = nthOutcomingDart c . dartIdByCrossingLegId (crossingState c)


makeCrossing' :: (CrossingType ct) => ct -> CrossingState ct
makeCrossing' = flip makeCrossing D4.i
