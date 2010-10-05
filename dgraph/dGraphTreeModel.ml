(**************************************************************************)
(*                                                                        *)
(*  This file is part of OcamlGraph.                                      *)
(*                                                                        *)
(*  Copyright (C) 2009-2010                                               *)
(*    CEA (Commissariat � l'�nergie Atomique)                             *)
(*                                                                        *)
(*  you can redistribute it and/or modify it under the terms of the GNU   *)
(*  Lesser General Public License as published by the Free Software       *)
(*  Foundation, version 2.1, with a linking exception.                    *)
(*                                                                        *)
(*  It is distributed in the hope that it will be useful,                 *)
(*  but WITHOUT ANY WARRANTY; without even the implied warranty of        *)
(*  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the         *)
(*  GNU Lesser General Public License for more details.                   *)
(*                                                                        *)
(*  See the file ../LICENSE for more details.                             *)
(*                                                                        *)
(*  Authors:                                                              *)
(*    - Julien Signoles  (Julien.Signoles@cea.fr)                         *)
(*    - Jean-Denis Koeck (jdkoeck@gmail.com)                              *)
(*    - Benoit Bataille  (benoit.bataille@gmail.com)                      *)
(*                                                                        *)
(**************************************************************************)

(* BUILDING A TREE MODEL FROM A GRAPH - EXPLORING FROM A VERTEX *)
open Graph

module SubTreeMake (G : Graphviz.GraphWithDotAttrs) = struct

  module Tree = Imperative.Digraph.Abstract(G.V)
  module TreeManipulation = DGraphSubTree.Manipulate(G)(Tree)

  type cluster = string

  class tree_model layout tree
    : [Tree.V.t, Tree.E.t, cluster] DGraphModel.abstract_model
    =
  let tree_structure = TreeManipulation.get_structure tree in
  object
    (* Iterators *)
    method iter_edges f = Tree.iter_edges
      (fun v1 v2 -> if TreeManipulation.is_ghost_node v1 tree
      && TreeManipulation.is_ghost_node v2 tree
      then () else f v1 v2) tree_structure

    method iter_edges_e f = Tree.iter_edges_e
      (fun e -> if TreeManipulation.is_ghost_edge e tree then () else f e)
      tree_structure

    method iter_pred f v = Tree.iter_pred
      (fun v -> if TreeManipulation.is_ghost_node v tree then () else f v)
      tree_structure v

    method iter_pred_e f v = Tree.iter_pred_e
      (fun e -> if TreeManipulation.is_ghost_edge e tree then () else f e)
      tree_structure v

    method iter_succ f = Tree.iter_succ
      (fun v -> if TreeManipulation.is_ghost_node v tree then () else f v)
      tree_structure

    method iter_succ_e f = Tree.iter_succ_e
      (fun e -> if TreeManipulation.is_ghost_edge e tree then () else f e)
      tree_structure

    method iter_vertex f = Tree.iter_vertex
      (fun v -> if TreeManipulation.is_ghost_node v tree then () else f v)
      tree_structure

    method iter_associated_vertex f v =
      let origin_vertex = TreeManipulation.get_graph_vertex v tree in
      List.iter
	(fun v -> if TreeManipulation.is_ghost_node v tree then () else f v)
	(TreeManipulation.get_tree_vertices origin_vertex tree)

    method iter_clusters f =
      Hashtbl.iter (fun k v -> f k) layout.XDot.cluster_layouts

    (* Membership functions *)
    method find_edge = try Tree.find_edge tree_structure
      with Not_found -> assert false
    method mem_edge = Tree.mem_edge tree_structure
    method mem_edge_e = Tree.mem_edge_e tree_structure
    method mem_vertex = Tree.mem_vertex tree_structure
    method src = Tree.E.src
    method dst = Tree.E.dst

    (* Layout *)
    method bounding_box = layout.XDot.bbox

    method get_vertex_layout v =
      try Hashtbl.find layout.XDot.vertex_layouts v
      with Not_found -> assert false

    method get_edge_layout e =
      try Hashtbl.find layout.XDot.edge_layouts e
      with Not_found -> assert false

    method get_cluster_layout c =
      try Hashtbl.find layout.XDot.cluster_layouts c
      with Not_found -> assert false

  end

  let tree = ref None
  let get_tree () = !tree

  let from_graph
      ?(cmd="dot")
      ?(tmp_name = "dgraph")
      ?(depth_forward=3)
      ?(depth_backward=3)
      context
      g
      v
      =

    (* Generate subtree *)
    tree := Some (TreeManipulation.make g v depth_forward depth_backward);
    let tree = match !tree with None -> assert false | Some t -> t in
    let tree_structure = TreeManipulation.get_structure tree in

    let module Attributes = struct
      let graph_attributes  _ = G.graph_attributes g

      let default_vertex_attributes _ = G.default_vertex_attributes g
      let cpt = ref 0
      let name_table = Hashtbl.create 100
      let vertex_name v =
	if Hashtbl.mem name_table v then
	  ( try Hashtbl.find name_table v with Not_found -> assert false)
	else begin
	  incr cpt;
	  Hashtbl.add name_table v (string_of_int !cpt);
	  string_of_int !cpt
	end
      let vertex_attributes v =
	if TreeManipulation.is_ghost_node v tree then
	  [ `Style `Invis ]
	else
	  G.vertex_attributes (TreeManipulation.get_graph_vertex v tree)

      let default_edge_attributes _ = []
      let edge_attributes e =
	if TreeManipulation.is_ghost_node (Tree.E.src e) tree
	|| TreeManipulation.is_ghost_node (Tree.E.dst e) tree
	then
	  [ `Style `Dashed; `Dir `None ]
	else
	  G.edge_attributes
	    (G.find_edge g
	      (TreeManipulation.get_graph_vertex (Tree.E.src e) tree)
	      (TreeManipulation.get_graph_vertex (Tree.E.dst e) tree))

      let get_subgraph v =
	if TreeManipulation.is_ghost_node v tree then
	  None
	else
	  G.get_subgraph (TreeManipulation.get_graph_vertex v tree)

    end in

    let module TreeLayout =
      DGraphTreeLayout.Make (struct include Tree include Attributes end)
    in
    let layout =
      TreeLayout.from_tree context tree_structure
	(TreeManipulation.get_root tree)
    in
    new tree_model layout tree

end

module SubTreeDotModelMake = struct

  module Tree = Imperative.Digraph.Abstract(DGraphModel.DotG.V)
  module TreeManipulation = DGraphSubTree.FromDotModel(Tree)

  type cluster = string

  class tree_model layout tree
    : [Tree.V.t, Tree.E.t, cluster] DGraphModel.abstract_model
    =
  let tree_structure = TreeManipulation.get_structure tree in
  object
    (* Iterators *)
    method iter_edges f = Tree.iter_edges
      (fun v1 v2 -> if TreeManipulation.is_ghost_node v1 tree
      && TreeManipulation.is_ghost_node v2 tree
      then () else f v1 v2) tree_structure

    method iter_edges_e f = Tree.iter_edges_e
      (fun e -> if TreeManipulation.is_ghost_edge e tree then () else f e)
      tree_structure

    method iter_pred f v = Tree.iter_pred
      (fun v -> if TreeManipulation.is_ghost_node v tree then () else f v)
      tree_structure v

    method iter_pred_e f v = Tree.iter_pred_e
      (fun e -> if TreeManipulation.is_ghost_edge e tree then () else f e)
      tree_structure v

    method iter_succ f = Tree.iter_succ
      (fun v -> if TreeManipulation.is_ghost_node v tree then () else f v)
      tree_structure

    method iter_succ_e f = Tree.iter_succ_e
      (fun e -> if TreeManipulation.is_ghost_edge e tree then () else f e)
      tree_structure

    method iter_vertex f = Tree.iter_vertex
      (fun v -> if TreeManipulation.is_ghost_node v tree then () else f v)
      tree_structure

    method iter_associated_vertex f v =
      let origin_vertex = TreeManipulation.get_graph_vertex v tree in
      List.iter
	(fun v -> if TreeManipulation.is_ghost_node v tree then () else f v)
	(TreeManipulation.get_tree_vertices origin_vertex tree)

    method iter_clusters f =
      Hashtbl.iter (fun k _ -> f k) layout.XDot.cluster_layouts

    (* Membership functions *)
    method find_edge = try Tree.find_edge tree_structure
      with Not_found -> assert false
    method mem_edge = Tree.mem_edge tree_structure
    method mem_edge_e = Tree.mem_edge_e tree_structure
    method mem_vertex = Tree.mem_vertex tree_structure
    method src = Tree.E.src
    method dst = Tree.E.dst

    (* Layout *)
    method bounding_box = layout.XDot.bbox

    method get_vertex_layout v =
      try Hashtbl.find layout.XDot.vertex_layouts v
      with Not_found -> assert false

    method get_edge_layout e =
      try Hashtbl.find layout.XDot.edge_layouts e
      with Not_found -> assert false

    method get_cluster_layout c =
      try Hashtbl.find layout.XDot.cluster_layouts c
      with Not_found -> assert false

  end

  let tree = ref None
  let get_tree () = !tree

  let from_model ?(depth_forward=3) ?(depth_backward=3) model v =
    (* Generate subtree *)
    tree := Some (TreeManipulation.make model v depth_forward depth_backward);
    let tree = match !tree with None -> assert false | Some t -> t in
    let tree_structure = TreeManipulation.get_structure tree in
    let module TreeLayout =
      DGraphTreeLayout.MakeFromDotModel (Tree) in
    let layout =
      TreeLayout.from_model tree_structure
	(TreeManipulation.get_root tree) model
    in
    new tree_model layout tree

end
