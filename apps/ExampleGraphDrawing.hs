module Main (main) where

import Data.Array.IArray ((!))
import Control.Monad.Writer (execWriter, tell)
import Control.Monad (forM_)
import Diagrams.Prelude
import Math.Topology.Manifolds.SurfaceGraph
import TestUtil.Drawing


main :: IO ()
main = do
    let g = nthBarycentricSubdivision (2 :: Int) $ constructFromList [[(0, 1), (0, 0)]]
    --let g = constructFromList [[(0, 1), (0, 0)]]
    --let e = embeddingWithFaceRooting (3 :: Int) (head $ graphFaces g)
    let e = embeddingInCircleWithVertexRooting (3 :: Int) (head $ allVertices g)
    writeSVGImage "example-graph-drawing.svg" (Width 1000) $ execWriter $
        forM_ (allEdges g) $ \ (a, _) -> do
            tell $ lineWidth 0.006 $ fromVertices $ map p2 $ e ! a
            forM_ (e ! a) $ \ p ->
                tell $ translate (r2 p) $ lineWidth 0 $ circle 0.01
            tell $ dashing [0.05, 0.02] 0 $ lineWidth 0.004 $ circle 1