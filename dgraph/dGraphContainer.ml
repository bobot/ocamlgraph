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

open Graph

let ($) f x = f x
let get_some = function None -> assert false | Some t -> t

type cluster = string

type status = Global | Tree | Both

(* ABSTRACT CLASS *)

class type ['vertex, 'edge, 'cluster,
'tree_vertex, 'tree_edge, 'tree_cluster] abstract_view_container = object
  method content : GPack.paned
  method global_view :
    ('vertex, 'edge, 'cluster) DGraphView.view option
  method tree_view :
    ('tree_vertex, 'tree_edge, 'tree_cluster) DGraphView.view option
  method set_tree_view : 'vertex -> unit
  method depth_backward : int
  method depth_forward : int
  method set_depth_backward : int -> unit
  method set_depth_forward : int -> unit
  method status : status
  method switch : status -> unit
end

(* CONTAINER *)

let with_commands ?packing container =
  let main_table = GPack.table
    ~columns:2
    ~rows:2
    ?packing () in

  (* Viewer *)
  main_table#attach
    ~left:0
    ~right:2
    ~top:1
    ~expand:`BOTH
    container#content#coerce;

  (* View controls *)
  let button_top_box = GPack.button_box
    `HORIZONTAL
    ~border_width:3
    ~child_height:10
    ~child_width:85
    ~spacing:10
    ~layout:`START
    ~packing:(main_table#attach ~top:0 ~left:0 ~expand:`X) ()
  in
  let view_label = GMisc.label ~markup:"<b>View</b>" () in
  button_top_box#pack ~expand:false view_label#coerce;
  let button_global_view =
    GButton.button ~label:"Global" ~packing:button_top_box#pack ()
  in
  let button_tree_view =
    GButton.button ~label:"Tree" ~packing:button_top_box#pack ()
  in
  let button_paned_view =
    GButton.button ~label:"Both" ~packing:button_top_box#pack ()
  in
  ignore $ button_global_view#connect#clicked
    ~callback:(fun _ -> container#switch Global) ;
  ignore $ button_tree_view#connect#clicked
    ~callback:(fun _ -> container#switch Tree) ;
  ignore $ button_paned_view#connect#clicked
    ~callback:(fun _ -> container#switch Both) ;

  (* Depth of exploration controls *)
  let depth_hbox = GPack.hbox
    ~packing:(main_table#attach ~expand:`X ~top:0 ~left:1) ()
  in
  let depth_forward_adj = GData.adjustment ~lower:0. ~page_size:0. () in
  let depth_backward_adj = GData.adjustment ~lower:0. ~page_size:0. () in
  let change_depth_forward adj content () =
    content#set_depth_forward (int_of_float adj#value);
  in
  let change_depth_backward adj content () =
    content#set_depth_backward (int_of_float adj#value)
  in
  ignore $ depth_forward_adj#connect#value_changed
    ~callback:(change_depth_forward depth_forward_adj container);
  ignore $ depth_backward_adj#connect#value_changed
    ~callback:(change_depth_backward depth_backward_adj container);
  let depth_label = GMisc.label ~markup:"<b>Depth</b>" () in
  let depth_forward_label = GMisc.label ~text:" forward: " () in
  let depth_backward_label = GMisc.label ~text:" backward: " () in
  let depth_forward_spin = GEdit.spin_button ~value:3.
    ~adjustment:depth_forward_adj () in
  let depth_backward_spin = GEdit.spin_button ~value:3.
    ~adjustment:depth_backward_adj () in
  depth_hbox#pack ~from:`END depth_backward_spin#coerce;
  depth_hbox#pack ~from:`END depth_backward_label#coerce;
  depth_hbox#pack ~from:`END depth_forward_spin#coerce;
  depth_hbox#pack ~from:`END depth_forward_label#coerce;
  depth_hbox#pack ~from:`END depth_label#coerce;

  main_table;;

(* FROM GRAPH *)

module Make ( G : Graphviz.GraphWithDotAttrs ) = struct

  module Choose = Oper.Choose(G)

  module TreeModel = DGraphTreeModel.SubTreeMake(G)

  class view_container global_view_fun tree_view_fun v g =

    let paned_window = GPack.paned `VERTICAL ~packing:(fun _ -> ()) () in
    let global_frame = GBin.frame ~label:"Global View" () in
    let tree_frame = GBin.frame ~label:"Tree View" () in
    let scrolled_global_view = GBin.scrolled_window
      ~hpolicy:`AUTOMATIC
      ~vpolicy:`AUTOMATIC
      ~packing:global_frame#add
      ()
    in
    let scrolled_tree_view = GBin.scrolled_window
      ~hpolicy:`AUTOMATIC
      ~vpolicy:`AUTOMATIC
      ~packing:tree_frame#add
      ()
    in

    (* [JS 2010/09/09] To factorize with the same code in the other functor *)

    (* Callback functions *)
    let connect_tree_callback obj node =
      let callback = function
	| `BUTTON_PRESS _ ->
	  obj#set_tree_view (TreeModel.Tree.V.label node#item);
	  false
	|_ -> false
      in
      node#connect_event ~callback
    in

    let connect_global_callback obj node =
      let callback = function
	| `BUTTON_PRESS _ ->
	  (match obj#status with
	  | Global -> ()
	  | Both ->
	    obj#set_tree_view node#item;
	    let tree_view = get_some obj#tree_view in
	    tree_view#adapt_zoom ()
	  | Tree -> assert false);
	  false
	|_ -> false
      in
      node#connect_event ~callback
    in

    let connect_switch_tree_callback obj node =
      let global_view = ((get_some obj#global_view) :>
	(G.V.t, G.E.t, string) DGraphView.view)
      in
      let tree = get_some (TreeModel.get_tree()) in
      let callback = function
	| `MOTION_NOTIFY _ ->
	  global_view#highlight (global_view#get_node
	    (TreeModel.TreeManipulation.get_graph_vertex node#item tree));
	  false
	| `LEAVE_NOTIFY _ ->
	  global_view#dehighlight (global_view#get_node
	    (TreeModel.TreeManipulation.get_graph_vertex node#item tree));
	  false
	| `BUTTON_PRESS _ ->
	  global_view#dehighlight (global_view#get_node
	    (TreeModel.TreeManipulation.get_graph_vertex node#item tree));
	  false
	|_ -> false
      in node#connect_event ~callback
    in

    let connect_switch_global_callback obj node =
      let tree_view = ((get_some obj#tree_view) :>
	(TreeModel.Tree.V.t,TreeModel.Tree.E.t,string) DGraphView.view)
      in
      let tree = get_some (TreeModel.get_tree ()) in
      let callback = function
	| `MOTION_NOTIFY _ ->
	  List.iter (fun v -> tree_view#highlight (tree_view#get_node v))
	  (TreeModel.TreeManipulation.get_tree_vertices node#item tree);
	  false
	| `LEAVE_NOTIFY _ ->
	  List.iter (fun v -> tree_view#dehighlight (tree_view#get_node v))
	  (TreeModel.TreeManipulation.get_tree_vertices node#item tree);
	  false
	|_ -> false
      in node#connect_event ~callback
    in

    object (self)
      val mutable global_view = (None :
	(G.V.t, G.E.t,string) DGraphView.view option)
      val mutable tree_view = (None :
	(TreeModel.Tree.V.t, TreeModel.Tree.E.t,string)
	DGraphView.view option)
      val mutable status = Global
      val mutable depth_forward = 3
      val mutable depth_backward = 3

      (* Getters *)
      method status = status
      method global_view = global_view
      method tree_view = tree_view
      method content = paned_window
      method depth_forward = depth_forward
      method depth_backward = depth_backward

      (* Setters *)
      method set_depth_forward i = depth_forward <- i
      method set_depth_backward i = depth_backward <- i

      method set_tree_view v =
	let model = TreeModel.from_graph
	  ~depth_forward:depth_forward
	  ~depth_backward:depth_backward
	  paned_window#as_widget g v
	in
	if tree_view != None then
	  scrolled_tree_view#remove scrolled_tree_view#child;
	let view = tree_view_fun model in
	scrolled_tree_view#add view#coerce;
	tree_view <- Some(view);
	view#connect_highlighting_event();
	view#iter_nodes (connect_tree_callback self);
	if status = Both then begin
	view#iter_nodes (connect_switch_tree_callback self);
	(get_some global_view)#iter_nodes
	  (connect_switch_global_callback self)
	end

      method private init_global_view () =
	let module GraphModel = DGraphModel.Make(G) in
	let model = GraphModel.from_graph g in
	let view = global_view_fun model in
	scrolled_global_view#add view#coerce;
	global_view <- Some(view);
	view#connect_highlighting_event();
	view#iter_nodes (connect_global_callback self)

      (* Switch *)
      method private switch_to_global_view () =
	if global_view = None then self#init_global_view ();
	(match status with
	  |Global -> ()
	  |Both ->
	    status <- Global;
	    paned_window#remove paned_window#child2
	  |Tree ->
	    status <- Global;
	    paned_window#remove paned_window#child2;
	    paned_window#add1 global_frame#coerce);
	(get_some global_view)#adapt_zoom()

      method private switch_to_tree_view () =
	if tree_view = None then
	  self#set_tree_view v;
	(match status with
	  |Tree -> ()
	  |Both ->
	    status <- Tree;
	    paned_window#remove paned_window#child1
	  |Global ->
	    status <- Tree;
	    paned_window#remove paned_window#child1;
	    paned_window#add2 tree_frame#coerce);
	(get_some tree_view)#adapt_zoom()

      method private switch_to_paned_view () =
	if tree_view = None then
	  self#set_tree_view v;
	if global_view = None then self#init_global_view ();
	(get_some tree_view)#iter_nodes (connect_switch_tree_callback self);
	(get_some global_view)#iter_nodes
	  (connect_switch_global_callback self);
	(match status with
	  |Both -> ()
	  |Global ->
	    status <- Both;
	    paned_window#add2 tree_frame#coerce
	  |Tree ->
	    status <- Both;
	    paned_window#add1 global_frame#coerce);
	(get_some global_view)#adapt_zoom();
	(get_some tree_view)#adapt_zoom()

      method switch = function
	|Global -> self#switch_to_global_view ()
	|Tree -> self#switch_to_tree_view ()
	|Both -> self#switch_to_paned_view ()

      (* Constructor *)
      initializer
	if (G.nb_vertex g < 1000 && G.nb_edges g < 10000) then begin
	  status <- Global;
	  self#init_global_view();
	  paned_window#add1 global_frame#coerce;
	  (get_some global_view)#adapt_zoom();
	end else begin
	  status <- Tree;
	  self#set_tree_view v;
	  paned_window#add2 tree_frame#coerce
	end
  end

  let from_graph
    ?(global_view = fun model -> DGraphView.view ~aa:true model)
    ?(tree_view = fun model -> DGraphView.view ~aa:true model)
    ?(vertex=None) g =
      match vertex with
	|None -> new view_container global_view tree_view
	  (Choose.choose_vertex g) g
	|Some v -> new view_container global_view tree_view v g;;

  let from_graph_with_commands ?packing ?global_view ?tree_view ?vertex g =
      with_commands ?packing (from_graph ?global_view ?tree_view ?vertex g);;

end

(* FROM DOT *)

module DotMake = struct

  module TreeModel = DGraphTreeModel.SubTreeDotModelMake

  class dot_view_container global_view_fun tree_view_fun dot_file =

    let paned_window = GPack.paned `VERTICAL ~packing:(fun _ -> ()) ()
    and global_frame = GBin.frame ~label:"Global View" ()
    and tree_frame = GBin.frame ~label:"Tree View" ()
    in
    let scrolled_global_view = GBin.scrolled_window
      ~hpolicy:`AUTOMATIC
      ~vpolicy:`AUTOMATIC
      ~packing:global_frame#add ()
    and scrolled_tree_view = GBin.scrolled_window
      ~hpolicy:`AUTOMATIC
      ~vpolicy:`AUTOMATIC
      ~packing:tree_frame#add ()
    in

    (* Callback functions *)
    let connect_tree_callback obj node =
      let callback = function
	| `BUTTON_PRESS _ ->
	  obj#set_tree_view (TreeModel.Tree.V.label node#item);
	  false
	|_ -> false
      in node#connect_event ~callback
    in

    let connect_global_callback obj node =
      let callback = function
	| `BUTTON_PRESS _ ->
	  (match obj#status with
	  | Global -> ()
	  | Both ->
	    obj#set_tree_view node#item;
	    let tree_view = get_some obj#tree_view in
	    tree_view#adapt_zoom ()
	  | Tree -> assert false);
	  false
	|_ -> false
      in node#connect_event ~callback
    in

    let connect_switch_tree_callback obj node =
      let global_view = ((get_some obj#global_view) :>
	(DGraphModel.DotG.V.t, DGraphModel.DotG.E.t, string) DGraphView.view)
      in
      let tree = get_some (TreeModel.get_tree()) in
      let callback = function
	| `MOTION_NOTIFY _ ->
	  global_view#highlight (global_view#get_node
	    (TreeModel.TreeManipulation.get_graph_vertex node#item tree));
	  false
	| `LEAVE_NOTIFY _ ->
	  global_view#dehighlight (global_view#get_node
	    (TreeModel.TreeManipulation.get_graph_vertex node#item tree));
	  false
	| `BUTTON_PRESS _ ->
	  global_view#dehighlight (global_view#get_node
	    (TreeModel.TreeManipulation.get_graph_vertex node#item tree));
	  false
	|_ -> false
      in node#connect_event ~callback
    in

    let connect_switch_global_callback obj node =
      let tree_view = ((get_some obj#tree_view) :>
	(TreeModel.Tree.V.t,TreeModel.Tree.E.t,string) DGraphView.view)
      in
      let tree = get_some (TreeModel.get_tree ()) in
      let callback = function
	| `MOTION_NOTIFY _ ->
	  List.iter (fun v -> tree_view#highlight (tree_view#get_node v))
	  (TreeModel.TreeManipulation.get_tree_vertices node#item tree);
	  false
	| `LEAVE_NOTIFY _ ->
	  List.iter (fun v -> tree_view#dehighlight (tree_view#get_node v))
	  (TreeModel.TreeManipulation.get_tree_vertices node#item tree);
	  false
	|_ -> false
      in node#connect_event ~callback
    in

    let global_model =
      if Filename.check_suffix dot_file "xdot" then
	DGraphModel.read_xdot dot_file
      else
	DGraphModel.read_dot dot_file
    in

    object (self)
      val mutable global_view = (None :
	(DGraphModel.DotG.V.t, DGraphModel.DotG.E.t,string)
	DGraphView.view option)
      val mutable tree_view = (None :
	(TreeModel.Tree.V.t, TreeModel.Tree.E.t,string)
	DGraphView.view option)
      val mutable status = Global
      val mutable depth_forward = 3
      val mutable depth_backward = 3

      (* Getters *)
      method status = status
      method global_view = global_view
      method tree_view = tree_view
      method content = paned_window
      method depth_forward = depth_forward
      method depth_backward = depth_backward

      (* Setters *)
      method set_depth_forward i = depth_forward <- i
      method set_depth_backward i = depth_backward <- i

      method set_tree_view vertex =
	let model = TreeModel.from_model
	  ~depth_forward:depth_forward
	  ~depth_backward:depth_backward
	  global_model vertex
	in
	if tree_view <> None then
	  scrolled_tree_view#remove scrolled_tree_view#child;
	let view = tree_view_fun model in
	scrolled_tree_view#add view#coerce;
	tree_view <- Some view;
	view#connect_highlighting_event();
	view#iter_nodes (connect_tree_callback self);
	if status = Both then begin
	view#iter_nodes (connect_switch_tree_callback self);
	(get_some global_view)#iter_nodes (connect_switch_global_callback self)
	end

      method private init_global_view () =
	let view = global_view_fun global_model in
	scrolled_global_view#add view#coerce;
(*	view#adapt_zoom ();
	ignore (view#set_center_scroll_region true);*)
	view#connect_highlighting_event ();
	view#iter_nodes (connect_global_callback self);
	global_view <- Some view;

      (* Switch *)
      method private switch_to_global_view () =
	if global_view = None then self#init_global_view ();
	match status with
	  |Global -> ()
	  |Both ->
	    status <- Global;
	    paned_window#remove paned_window#child2
	  |Tree ->
	    status <- Global;
	    paned_window#remove paned_window#child2;
	    paned_window#add1 global_frame#coerce

      method private switch_to_tree_view () =
	if tree_view = None then begin
	  let vertex = ref None in
	  global_model#iter_vertex
	    (fun v -> if !vertex = None then vertex := Some v);
	  self#set_tree_view (get_some !vertex);
	end;
	match status with
	  |Tree -> ()
	  |Both ->
	    status <- Tree;
	    paned_window#remove paned_window#child1
	  |Global ->
	    status <- Tree;
	    paned_window#remove paned_window#child1;
	    paned_window#add2 tree_frame#coerce

      method private switch_to_paned_view () =
	if tree_view = None then begin
	  let vertex = ref None in
	  global_model#iter_vertex
	    (fun v -> if !vertex = None then vertex := Some v);
	  self#set_tree_view (get_some !vertex)
	end;
	if global_view = None then self#init_global_view ();
	(get_some tree_view)#iter_nodes (connect_switch_tree_callback self);
	(get_some global_view)#iter_nodes
	  (connect_switch_global_callback self);
	match status with
	  |Both -> ()
	  |Global ->
	    status <- Both;
	    paned_window#add2 tree_frame#coerce
	  |Tree ->
	    status <- Both;
	    paned_window#add1 global_frame#coerce

      method switch = function
	|Global -> self#switch_to_global_view ()
	|Tree -> self#switch_to_tree_view ()
	|Both -> self#switch_to_paned_view ()

      (* Constructor *)
      initializer
	  status <- Global;
	  self#init_global_view();
	  paned_window#add1 global_frame#coerce
  end

  let from_dot
    ?(global_view = fun model -> DGraphView.view ~aa:true model)
    ?(tree_view = fun model -> DGraphView.view ~aa:true model)
    dot_file =
      new dot_view_container global_view tree_view dot_file

  let from_dot_with_commands ?packing ?global_view ?tree_view dot_file =
      with_commands ?packing (from_dot ?global_view ?tree_view dot_file);;

end
