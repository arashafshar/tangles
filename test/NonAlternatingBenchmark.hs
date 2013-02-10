{-# LANGUAGE MultiParamTypeClasses #-}
module Main (main) where

import Data.Array.Base (listArray)
import Data.Maybe (mapMaybe)
import Control.Monad.Writer
import Text.Printf
import Diagrams.Prelude
import Math.KnotTh.Enumeration.DiagramInfo.MinimalDiagramInfo
import Math.KnotTh.Enumeration.Applied.NonAlternatingTangles
import Math.KnotTh.Draw.DrawKnot
import Math.KnotTh.Link.FromTangle
import Math.KnotTh.Tangle.Table
import Math.KnotTh.Tangle.Moves.Test
import Math.KnotTh.Link.Table
import TestUtil.Table
import TestUtil.Drawing


main :: IO ()
main = do
    printTable "Diagrams" $ generateTable' $ tangleDiagrams False (-1) 5

    let sifted = lookingForwardTanglesEnumeration True 6 0 6
    printTable "Tangles" $ generateTable' $ forM_ (mapMaybe maybePrimeDiagram $ singleRepresentativeClasses sifted)
    printf "Collision classes: %i" (length $ collisionClasses sifted)
    writeSVGImage "collisions.svg" (Width 500) $ pad 1.05 $ execWriter $
        forM_ (collisionClasses sifted `zip` [0 ..]) $ \ (cc, j) ->
            forM_ (cc `zip` [0 ..]) $ \ (info, i) ->
                tell $ translate (r2 (2.2 * i, -2.2 * j)) $ drawKnot defaultDraw $ representative info
