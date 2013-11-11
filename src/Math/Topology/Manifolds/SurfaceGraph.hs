module Math.Topology.Manifolds.SurfaceGraph
    ( module Def
    , module Util
    , module Bary
    , module E
    , module SS
    , Cell(..)
    ) where

import Math.Topology.Manifolds.SurfaceGraph.Definition as Def
import Math.Topology.Manifolds.SurfaceGraph.Util as Util
import Math.Topology.Manifolds.SurfaceGraph.Barycentric as Bary
import Math.Topology.Manifolds.SurfaceGraph.Embedding as E
import Math.Topology.Manifolds.SurfaceGraph.SphereStar as SS


data Cell = Cell0D Vertex | Cell1D Dart | Cell2D Face deriving (Eq, Ord)