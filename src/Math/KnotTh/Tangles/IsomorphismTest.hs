{-# LANGUAGE UnboxedTuples #-}
module Math.KnotTh.Tangles.IsomorphismTest
	( isomorphismTest
	, isomorphismTest'
	) where

import Prelude hiding (head, tail)
import Data.Bits (shiftL)
import Data.Function (fix)
import Data.STRef (newSTRef, readSTRef, writeSTRef)
import Data.Array.Base (unsafeRead, unsafeWrite)
import Data.Array.Unboxed (UArray)
import Data.Array.ST (STArray, STUArray, runSTUArray, newArray, newArray_)
import Control.Monad.ST (ST)
import Control.Monad (when, foldM_)
import Math.Algebra.RotationDirection (RotationDirection, ccw, cw)
import Math.KnotTh.Tangles


isomorphismTest' :: (CrossingType ct) => Tangle ct -> UArray Int Int
isomorphismTest' tangle = isomorphismTest (tangle, 0)


isomorphismTest :: (CrossingType ct) => (Tangle ct, Int) -> UArray Int Int
isomorphismTest tc = min (codeWithDirection ccw tc) (codeWithDirection cw tc)


codeWithDirection :: (CrossingType ct) => RotationDirection -> (Tangle ct, Int) -> UArray Int Int
codeWithDirection !dir (tangle, circles) = minimum [ code leg | leg <- allLegs tangle ]
	where
		n = numberOfCrossings tangle
		l = numberOfLegs tangle

		code leg = runSTUArray $ do
			index <- newArray (0, n) 0 :: ST s (STUArray s Int Int)
			queue <- newArray_ (0, n - 1) :: ST s (STArray s Int (Dart ct))
			free <- newSTRef 1

			let look !d
				| isLeg d    = return 0
				| otherwise  = do
					let u = incidentCrossing d
					ux <- unsafeRead index $! crossingIndex u
					if ux > 0
						then return $! ux
						else do
							nf <- readSTRef free
							writeSTRef free $! nf + 1
							unsafeWrite index (crossingIndex u) nf
							unsafeWrite queue (nf - 1) d
							return $! nf

			rc <- newArray_ (0, l + 2 * n) :: ST s (STUArray s Int Int)
			unsafeWrite rc 0 circles
			foldM_ (\ !d !i -> do { look (opposite d) >>= unsafeWrite rc i ; return $! nextDir dir d }) leg [1 .. l]

			flip fix 0 $ \ bfs !head -> do
				tail <- readSTRef free
				when (head < tail - 1) $ do
					input <- unsafeRead queue head
					nb <- foldMAdjacentDartsFrom input dir (\ !d !s -> do { c <- look d ; return $! c + s `shiftL` 7 }) 0
					case crossingCode dir input of
						(# be, le #) -> do
							unsafeWrite rc (l + 1 + 2 * head) be
							unsafeWrite rc (l + 2 + 2 * head) $! le + nb `shiftL` 3
					bfs $! head + 1

			fix $ \ recheck -> do
				tail <- readSTRef free
				when (tail <= n) $
					fail "codeWithDirection: not connected diagram"
					recheck

			return $! rc