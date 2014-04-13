module Math.Topology.KnotTh.Tangle.Braid
    ( (|=|)
    , (|~|)
    , identityBraidTangle
    , braidGeneratorTangle
    , braidTangle
    , reversingBraidTangle
    ) where

import Text.Printf
import Math.Topology.KnotTh.Knotted
import Math.Topology.KnotTh.Tangle.TangleLike
import Math.Topology.KnotTh.Tangle.Tangle


(|=|) :: (TangleLike t) => t a -> t a -> t a
(|=|) a b
    | al /= bl   = error $ printf "braidLikeGlue: different numbers of legs (%i and %i)" al bl
    | otherwise  = glueTangles n (nthLeg a n) (nthLeg b (n - 1))
    where
        al = numberOfLegs a
        bl = numberOfLegs b
        n = al `div` 2


(|~|) :: (TangleLike t) => t a -> t a -> t a
(|~|) a b =
    let k = numberOfLegs a `div` 2
    in rotateTangle (-k) $ glueTangles 0 (nthLeg a k) (firstLeg b)


identityBraidTangle :: Int -> Tangle a
identityBraidTangle n
    | n < 0      = error $ printf "identityBraidTangle: requested number of strands %i is negative" n
    | otherwise  =
        let n' = 2 * n - 1
        in implode (0, [(0, n' - i) | i <- [0 .. n']], [])


braidGeneratorTangle :: Int -> (Int, a) -> Tangle a
braidGeneratorTangle n (k, s)
    | n < 2               = error $ printf "braidGeneratorTangle: braid must have at least 2 strands, but %i requested" n
    | k < 0 || k > n - 2  = error $ printf "braidGeneratorTangle: generator offset %i is out of bounds (0, %i)" k (n - 2)
    | otherwise           =
        let n' = 2 * n - 1
            k' = n' - k - 1
            b = map $ \ i -> (0, n' - i)
        in implode
            ( 0
            , concat [b [0 .. k - 1], [(1, 0), (1, 1)], b [k + 2 .. k' - 1], [(1, 2), (1, 3)], b [k' + 2 .. n']]
            , [([(0, k), (0, k + 1), (0, k'), (0, k' + 1)], s)]
            )


braidTangle :: Int -> [(Int, a)] -> Tangle a
braidTangle n = foldl (\ braid -> (braid |=|) . braidGeneratorTangle n) (identityBraidTangle n)


reversingBraidTangle :: Int -> a -> Tangle a
reversingBraidTangle n s
    | n < 0      = error $ printf "flipBraidTangle: requested number of strands %i is negative" n
    | otherwise  = braidTangle n [ (i, s) | k <- [2 .. n], i <- [0 .. n - k] ]