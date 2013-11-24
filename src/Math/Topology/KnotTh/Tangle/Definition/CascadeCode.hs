module Math.Topology.KnotTh.Tangle.Definition.CascadeCode
    ( CascadeCodePattern(..)
    , decodeCascadeCode
    , ProjPattern(..)
    , DiagPattern(..)
    , decodeCascadeCodeFromPairs
    ) where

import Data.Char (isSpace)
import Text.Printf
import Math.Topology.KnotTh.Crossings.Projection
import Math.Topology.KnotTh.Crossings.Diagram
import Math.Topology.KnotTh.Knotted
import Math.Topology.KnotTh.Tangle.Definition.TangleLike
import Math.Topology.KnotTh.Tangle.Definition.Tangle
import Math.Topology.KnotTh.Tangle.Definition.Transform


data ProjPattern = W | X | M deriving (Eq, Enum, Show, Read)


class (Enum pattern, CrossingType ct) => CascadeCodePattern pattern ct | pattern -> ct where
    cascadeCodeRoot :: [(pattern, Int)] -> Tangle ct
    decodeCrossing  :: pattern -> (ProjPattern, Int, Int, CrossingState ct)


decodeCascadeCode :: (CascadeCodePattern p ct) => [(p, Int)] -> Tangle ct
decodeCascadeCode code =
    foldl
        (\ prev (pattern, offset) ->
            let (gl, shift, rot, c) = decodeCrossing pattern
                p | rot == 0   = id
                  | otherwise  = rotateTangle rot
            in p $ vertexOwner $ glueToBorder
                (nthLeg prev $ offset + shift)
                (case gl of { W -> 3 ; X -> 2 ; M -> 1 })
                c
        )
        (cascadeCodeRoot code)
        code


instance CascadeCodePattern ProjPattern ProjectionCrossing where
    cascadeCodeRoot _ = lonerTangle projectionCrossing

    decodeCrossing W = (W, 1, 0, projectionCrossing)
    decodeCrossing X = (X, 1, 0, projectionCrossing)
    decodeCrossing M = (M, 0, -1, projectionCrossing)


data DiagPattern = WO | WU | XO | XU | MO | MU deriving (Eq, Enum)


instance Show DiagPattern where
    show p = case p of
        WO -> "W+"
        WU -> "W-"
        XO -> "X+"
        XU -> "X-"
        MO -> "M+"
        MU -> "M-"


instance Read DiagPattern where
    readsPrec _ s = case dropWhile isSpace s of
        'W' : '+' : t -> [(WO, t)]
        'W' : '-' : t -> [(WU, t)]
        'X' : '+' : t -> [(XO, t)]
        'X' : '-' : t -> [(XU, t)]
        'M' : '+' : t -> [(MO, t)]
        'M' : '-' : t -> [(MU, t)]
        _             -> []


instance CascadeCodePattern DiagPattern DiagramCrossing where
    cascadeCodeRoot _ = lonerTangle overCrossing

    decodeCrossing WO = (W, 1, 0, underCrossing)
    decodeCrossing WU = (W, 1, 0, overCrossing)
    decodeCrossing XO = (X, 1, 0, overCrossing)
    decodeCrossing XU = (X, 1, 0, underCrossing)
    decodeCrossing MO = (M, 0, -1, overCrossing)
    decodeCrossing MU = (M, 0, -1, underCrossing)


decodeCascadeCodeFromPairs :: [(Int, Int)] -> Tangle ProjectionCrossing
decodeCascadeCodeFromPairs = (decodeCascadeCode .) $ map $ \ (p, off) ->
    flip (,) off $ case p of
        -1 -> W
        0  -> X
        1  -> M
        _  -> error $ printf "decodeCascadeCodeFromPairs: expected -1, 0 or 1 as pattern, %i received" p
