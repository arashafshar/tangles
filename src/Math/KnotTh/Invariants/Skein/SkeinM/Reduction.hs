module Math.KnotTh.Invariants.Skein.SkeinM.Reduction
	( internalEdgesST
	, greedyReductionST
	) where

import Control.Monad.ST (ST)
import Control.Monad (forM, unless)
import Math.KnotTh.Invariants.Skein.Relation
import Math.KnotTh.Invariants.Skein.SkeinM.State
import Math.KnotTh.Invariants.Skein.SkeinM.RelaxVertex
import Math.KnotTh.Invariants.Skein.SkeinM.ContractEdge


internalEdgesST :: SkeinState s r a -> ST s [(Int, Int)]
internalEdgesST s = do
	vs <- aliveVerticesST s
	fmap concat $ forM vs $ \ v -> do
		d <- vertexDegreeST s v
		fmap concat $ forM [0 .. d - 1] $ \ p -> do
			(u, q) <- neighbourST s (v, p)
			return $ if u > v || (u == v && q > p)
				then [(v, p)]
				else []


greedyReductionST :: (SkeinRelation r a) => SkeinState s r a -> ST s ()
greedyReductionST s = do
	mv <- dequeueST s
	case mv of
		Nothing -> return ()
		Just v  -> do
			let tryReductions [] = return ()
			    tryReductions (h : t) = do
			    	r <- h s v
			    	unless r $ tryReductions t

			tryReductions [tryRelaxVertex, tryGreedyContract]
			greedyReductionST s
