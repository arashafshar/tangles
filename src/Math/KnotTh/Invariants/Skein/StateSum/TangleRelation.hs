module Math.KnotTh.Invariants.Skein.StateSum.TangleRelation
    ( extractTangle
    , tangleInSkeinBasis
    ) where

import Data.Function (on)
import Data.Array.Base ((!), array)
import Data.Array (Array)
import Math.KnotTh.Knotted.Threads
import Math.KnotTh.Tangle.NonAlternating
import Math.KnotTh.Tangle.Moves.Move
import Math.KnotTh.Tangle.Moves.ReidemeisterReduction
import Math.KnotTh.Invariants.Skein.StateSum.Summand
--import Math.KnotTh.Invariants.Skein.StateSum.Sum


extractTangle :: StateSummand a -> NonAlternatingTangle
extractTangle = undefined


tangleInSkeinBasis :: NonAlternatingTangle -> [NonAlternatingTangle]
tangleInSkeinBasis tangle =
    let (n, marks, threads) = allThreadsWithMarks tangle

        threadIndex :: Array Int Int
        threadIndex = array (1, n) $ flip map threads $ \ (i, thread) ->
            case thread of
                [] -> (i, undefined)
                _  -> (i, on min legPlace (fst $ head thread) (snd $ last thread))

        order :: Array Int Int
        order = array (dartIndexRange tangle) $ do
            (_, thread) <- threads
            (i, (a, b)) <- zip [0 ..] thread
            [(dartIndex a, 2 * i), (dartIndex b, 2 * i + 1)]

        tryCrossing [] = return $! tangle
        tryCrossing (c : rest) = do
            let [d0, d1, d2, d3] = incidentDarts c
            if passOver d0 == on (<) ((\ d -> (threadIndex ! abs (marks ! d), order ! d)) . dartIndex) d0 d1
                then tryCrossing rest
                else let flipped = move tangle $ modifyC False invertCrossing [c]
                         smoothedZ = move tangle $ substituteC [(opposite d0, d1), (opposite d3, d2)] >> maskC [c]
                         smoothedI = move tangle $ substituteC [(opposite d0, d3), (opposite d1, d2)] >> maskC [c]
                     in concatMap (tangleInSkeinBasis . greedy1st2ndReduction) [flipped, smoothedZ, smoothedI]
    in tryCrossing $ allCrossings tangle
