module Math.Topology.KnotTh.Tangle.Moves.Flype
    ( neighbours
    ) where

import Data.Maybe (mapMaybe)
import Data.Array.Unboxed ((!))
import Control.Monad (guard)
import Math.Topology.KnotTh.Tangle
import Math.Topology.KnotTh.Tangle.Moves.Move
import Math.Topology.KnotTh.Tangle.Moves.Resting


neighbours :: NATangle -> [NATangle]
neighbours tangle =
    flip mapMaybe (allDartsOfCrossings tangle) $ \ ab -> do
        let ba = opposite ab
            ac = nextCCW ab
            ca = opposite ac

        guard $ isDart ba && isDart ca

        let a = incidentCrossing ab
            b = incidentCrossing ba
            c = incidentCrossing ca

        guard $ b /= c && a /= b && a /= c

        let ae = nextCCW ac
            ad = nextCW ab

        ((rp, sq), sub) <-
            restingPart tangle [ba, ca] >>= \ (lst, s) ->
                case lst of
                    [x, y] -> return ((x, y), s)
                    _      -> Nothing

        return $! move tangle $ do
            substituteC [(ba, ae), (ca, ad), (ab, rp), (ac, sq)]
            connectC [(rp, ae), (sq, ad)]
            modifyC True id $ filter ((sub !) . crossingIndex) $ allCrossings tangle