module Math.KnotTh.Invariants.JonesPolynomial
	( jonesPolynomialOfLink
	, minimalJonesPolynomialOfLink
	, kauffmanXPolynomialOfLink
	, minimalKauffmanXPolynomialOfLink
	, jonesPolynomialOfTangle
	, minimalJonesPolynomialOfTangle
	) where

import Data.List (sort, foldl')
import Data.Array.Unboxed (UArray, array, (!))
import Data.Array.ST (STUArray, newArray, getAssocs, readArray, writeArray)
import qualified Data.Set as Set
import qualified Data.Map as Map
import Control.Monad.ST (ST, runST)
import qualified Math.Projects.KnotTheory.LaurentMPoly as LP
import Math.KnotTh.Knotted
import Math.KnotTh.Crossings.Arbitrary
import qualified Math.KnotTh.Link.NonAlternating as L
import qualified Math.KnotTh.Tangle.NonAlternating as T


type Poly = LP.LaurentMPoly Int


jonesVar :: String
jonesVar = "t"


jonesA, jonesB :: Poly
jonesA = LP.LP [(LP.LM $ Map.fromList [(jonesVar, -1 / 4)], 1)]
jonesB = LP.LP [(LP.LM $ Map.fromList [(jonesVar,  1 / 4)], 1)]


kauffmanXVar :: String
kauffmanXVar = "A"


kauffmanXA, kauffmanXB :: Poly
kauffmanXA = LP.LP [(LP.LM $ Map.fromList [(kauffmanXVar,  1)], 1)]
kauffmanXB = LP.LP [(LP.LM $ Map.fromList [(kauffmanXVar, -1)], 1)]


invert :: String -> Poly -> Poly
invert var (LP.LP monomials) = sum $ do
	(LP.LM vars, coeff) <- monomials
	let modify p@(x, d)
		| x == var   = (x, -d)
		| otherwise  = p
	return $! LP.LP [(LP.LM $ Map.fromList $ map modify $ Map.toList vars, coeff)]


data Node a = Cross a a a a | Join a a deriving (Eq, Show, Read, Ord)

instance Functor Node where
	fmap f (Cross a b c d) = Cross (f a) (f b) (f c) (f d)
	fmap f (Join a b) = Join (f a) (f b)


kauffmanStateSums :: L.NonAlternatingLink -> [((Int, Int), Int)]
kauffmanStateSums link = runST $ do
	let n = numberOfCrossings link
	coeff <- newArray ((0, 0), (n, n + 1)) 0 :: ST s (STUArray s (Int, Int) Int)

	let kauffman !u !v list =
		case list of
			[]                          -> readArray coeff (u, v) >>= writeArray coeff (u, v) . (+ 1)
			Join a b : rest | a == b    -> kauffman u (v + 1) rest
			                | otherwise -> kauffman u v $! map (fmap $ \ x -> if x == a then b else x) rest
			Cross a b c d : rest        -> do
				kauffman u v $! Join a b : Join c d : rest
				kauffman (u + 1) v $! Join a d : Join b c : rest

	kauffman 0 0 $! flip map (allCrossings link) $ \ c ->
		let	label d = min (dartIndex d) (dartIndex $ opposite d)
			[d0, d1, d2, d3] = incidentDarts c
		in if passOver d0
			then Cross (label d0) (label d1) (label d2) (label d3)
			else Cross (label d1) (label d2) (label d3) (label d0)

	filter ((/= 0) . snd) `fmap` getAssocs coeff


kauffmanBracket :: (Num a) => a -> a -> L.NonAlternatingLink -> a
kauffmanBracket a b link = writheFactor * (b ^ numberOfCrossings link) * stateSum
	where
		writheFactor =
			let w = selfWrithe link
			in (if w <= 0 then -a else -b) ^ abs (3 * w)

		d = -(a * a + b * b)

		stateSum = sum $ flip map (kauffmanStateSums link) $ \ ((u, v), k) ->
			fromIntegral k * (a ^ (u + u)) * (d ^ (v + numberOfFreeLoops link - 1))


jonesPolynomialOfLink :: L.NonAlternatingLink -> Poly
jonesPolynomialOfLink = kauffmanBracket jonesA jonesB


minimalJonesPolynomialOfLink :: L.NonAlternatingLink -> Poly
minimalJonesPolynomialOfLink link =
	let jp = jonesPolynomialOfLink link
	in min jp (invert jonesVar jp)


kauffmanXPolynomialOfLink :: L.NonAlternatingLink -> Poly
kauffmanXPolynomialOfLink = kauffmanBracket kauffmanXA kauffmanXB


minimalKauffmanXPolynomialOfLink :: L.NonAlternatingLink -> Poly
minimalKauffmanXPolynomialOfLink link =
	let kp = kauffmanXPolynomialOfLink link
	in min kp (invert kauffmanXVar kp)


type Scheme = [(Int, Int)]


jonesPolynomialOfTangle :: T.NonAlternatingTangle -> [(Scheme, Poly)]
jonesPolynomialOfTangle tangle = map (\ (sch, poly) -> (sch, wm * cm * poly)) $ skein (allCrossings tangle) [] 1
	where
		jonesD = -(jonesA * jonesA + jonesB * jonesB)

		cm = jonesD ^ numberOfFreeLoops tangle

		wm =	let w = selfWrithe tangle
			in (if w >= 0 then -jonesB else -jonesA) ^ (3 * abs w)

		skein [] assocs mul =
			let (sch, poly) = reductionOutcome (array (crossingIndexRange tangle) assocs)
			in [(sch, mul * poly)]

		skein (c : rest) assocs mul = merge
			(skein rest ((crossingIndex c, False) : assocs) (jonesA * mul))
			(skein rest ((crossingIndex c, True) : assocs) (jonesB * mul))
			where
				merge [] bl = bl
				merge al [] = al
				merge al@(ae@(as, ap) : at) bl@(be@(bs, bp) : bt) =
					case compare as bs of
						LT             -> ae : merge at bl
						GT             -> be : merge al bt
						EQ | s == 0    -> merge at bt
						   | otherwise -> (as, s) : merge at bt
					where
						s = ap + bp

		reductionOutcome :: UArray Int Bool -> (Scheme, Poly)
		reductionOutcome reduction = (scheme, jonesD ^ circles)
			where
				circles = (length paths) - (length pairs)

				scheme =
					let toPositionPair (al, bl) = (min ap bp, max ap bp)
						where
							ap = T.legPlace al
							bp = T.legPlace bl
					in sort $ map toPositionPair pairs

				pairs = map (\ path -> (fst $ head path, snd $ last path)) $ filter (T.isLeg . fst . head) paths

				paths =
					let smooting drt
						| passOver drt == (reduction ! crossingIndex (incidentCrossing drt))  = nextCCW drt
						| otherwise                                                           = nextCW drt
					in undirectedPathsDecomposition smooting tangle


		containingDirectedPath (adjForward, adjBackward) start
			| isCycle    = forward
			| otherwise  = walkBackward (start, forward)
			where
				(forward, isCycle) = walkForward start

				walkForward d
					| T.isLeg opp   = ([d], False)
					| start == nxt  = ([d], True)
					| otherwise     = (d : nextPath, nextCycle)
					where
						opp = opposite d
						nxt = adjForward opp
						(nextPath, nextCycle) = walkForward nxt

				walkBackward (d, path)
					| T.isLeg d  = path
					| otherwise  = let prev = opposite $ adjBackward d in walkBackward (prev, prev : path)

		undirectedPathsDecomposition continue = fst . foldl' processDart ([], Set.empty) . allHalfEdges
			where
				processDart (!paths, s) d
					| Set.member d s  = (paths, s)
					| otherwise       = (path : paths, nextS)
					where
						path = containingUndirectedPath continue d
						nextS = foldl' (\ curs (a, b) -> Set.insert b $ Set.insert a curs) s path

				containingUndirectedPath cont = map (\ d -> (d, opposite d)) . containingDirectedPath (cont, cont)


minimalJonesPolynomialOfTangle :: T.NonAlternatingTangle -> [(Scheme, Poly)]
minimalJonesPolynomialOfTangle tangle = minimum $ do
	let jp = jonesPolynomialOfTangle tangle
	let l = T.numberOfLegs tangle
	rot <- [0 .. l - 1]

	f <-	let mapScheme f = map $ \ (a, b) -> 
			let a' = f a `mod` l
			    b' = f b `mod` l
			in (min a' b', max a' b')
		in
			[ \ (s, p) -> (sort $ mapScheme (+ rot) s, p)
			, \ (s, p) -> (sort $ mapScheme (+ rot) s, invert jonesVar p)
			, \ (s, p) -> (sort $ mapScheme (\ i -> rot - i) s, p)
			, \ (s, p) -> (sort $ mapScheme (\ i -> rot - i) s, invert jonesVar p)
			]

	return $! sort $! map f jp