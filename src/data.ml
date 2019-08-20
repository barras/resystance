open Core (* LambdaPi core *)
open Extra

module D = Distribution

(** A record containing all data from a file (or several files). *)
type t =
  { fname : string option
  (** Filename if separated output *)
  ; sym : int
  (** Number of symbols declared *)
  ; rul : int
  (** Number of rules declared *)
  ; nlr : int
  (** Number of nonlinear rules *)
  ; hor : int
  (** Number of higher order rules *)
  ; ari : D.t
  (** Distribution of the arity of rules*)
  ; siz : D.t
  (** Distribution of the size of the rules *)
  ; hgt : D.t
  (** Distribution of the height of the rules. *) }

let empty : t =
  { fname = None
  ; sym = 0
  ; rul = 0
  ; nlr = 0
  ; hor = 0
  ; ari = D.empty
  ; siz = D.empty
  ; hgt = D.empty }

let compile = Compile.compile true

(** [count_symbols s] counts the number of symbols declared in the
    signature [s]. *)
let count_symbols : Sign.t -> int = fun sign ->
  StrMap.cardinal Timed.(!(sign.sign_symbols))

(** [count_rules s] count the number of rules declared in the signature [s]. *)
let count_rules : Sign.t -> int = fun sign ->
  let rul_of_sym (sy:Terms.sym) = List.length Timed.(!(sy.sym_rules)) in
  StrMap.fold (fun _ (sy, _) -> (+) (rul_of_sym sy))
    Timed.(!(sign.sign_symbols)) 0

(** [nonlin r] returns true if rule [r] is left nonlinear. *)
let nonlin : Terms.rule -> bool = fun { lhs ; _ } ->
  let slots = List.to_seq lhs |>
                Seq.filter_map
                  (function Terms.Patt(io, _, _) -> io | _ -> None) |>
                List.of_seq in
  let slots_uniq = List.sort_uniq Int.compare slots in
  List.compare_lengths slots slots_uniq <> 0

(** [count_nlrules s] counts the number of non left linear rules in
    signature [s]. *)
let count_nlrules : Sign.t -> int = fun sign ->
  let nr_of_sym (sy:Terms.sym) =
    List.fold_left
      (fun acc rul -> if nonlin rul then acc + 1 else acc)
      0
      Timed.(!(sy.sym_rules)) in
  StrMap.fold (fun _ (sy, _) acc -> acc + (nr_of_sym sy))
    Timed.(!(sign.sign_symbols)) 0

(** [ho r] returns true if rule [r] contains higher order terms. *)
let ho : Terms.rule -> bool = fun { lhs ; _ } ->
  let rec ho te =
    let open Terms in
    match te with
    | Appl(t, u) -> ho t || ho u
    | Abst(_, _) -> true
    | _          -> false in
  List.exists ho lhs

(** [count_horules s] counts the number of higher order rules in
    signature [s]. *)
let count_horules : Sign.t -> int = fun sign ->
  let ho_of_sym (sy:Terms.sym) =
    List.fold_left
      (fun acc rul -> if ho rul then acc + 1 else acc)
      0
      Timed.(!(sy.sym_rules)) in
  StrMap.fold (fun _ (sy, _) acc -> acc + (ho_of_sym sy))
    Timed.(!(sign.sign_symbols)) 0

(** [height_of_rules r] returns the height of rule [r]. *)
let height_of_rule : Terms.rule -> int = fun { lhs ; _ } ->
  let open Terms in
  (* [depth t] returns the depth of term [t] defined as
     - [depth f t1 ... tn = 1 + max {depth t | t in t1 ... tn}]
     - [depth x = 0]. *)
  let rec depth : term -> int = function
    | Appl(u, v) -> max (depth u) (depth v) + 1
    | Abst(_, u) -> let _, u = Bindlib.unbind u in
      depth u + 1
    | _          -> 0 in
  depth (Basics.add_args Kind lhs) - 1

(** [rules_heights s] returns the distribution of heights of rules in
    signature [s]. *)
let rules_heights : Sign.t -> D.t = fun sign ->
  let heights_of_sym (sy:Terms.sym) : int list =
    List.map height_of_rule Timed.(!(sy.sym_rules)) in
  D.of_list @@
  StrMap.fold (fun _ (sy, _) acc -> heights_of_sym sy @ acc)
    Timed.(!(sign.sign_symbols)) []

(** [size_of_rule r] returns the size of the lhs of [r], the size
 ** being the number of (sub) terms. *)
let size_of_rule : Terms.rule -> int = fun { lhs ; _ } ->
  let open Terms in
  let rec sot : term -> int = function
    | Appl(u, v)    -> (sot u) + (sot v)
    | Abst(_, u)    -> let _, u = Bindlib.unbind u in sot u + 1
    | Symb(_, _)    -> 1
    | Vari(_)       -> 1
    | Patt(_, _, _) -> 1
    | _             -> assert false in
  sot (Basics.add_args Kind lhs) - 1

(** [rules_arity s] returns the distribution of the arity of the root symbol
    of the rules in signature [s]. *)
let rules_arity : Sign.t -> D.t = fun sign ->
  let open Terms in
  let sizes_of_sym (sy:sym) : int list =
    List.map (fun { lhs ; _ } -> List.length lhs) Timed.(!(sy.sym_rules)) in
  D.of_list @@
  StrMap.fold (fun _ (sy, _) acc -> (sizes_of_sym sy) @ acc)
    Timed.(!(sign.sign_symbols)) []

(** [rules_size s] returns the distribution of sizes of rules in
 ** signature [s]. *)
let rules_sizes : Sign.t -> D.t = fun sign ->
  let sizes_of_sym sy =
    List.map size_of_rule Timed.(Terms.(!(sy.sym_rules))) in
  D.of_list @@
    StrMap.fold (fun _ (sy, _) acc -> sizes_of_sym sy @ acc)
  Timed.(!(sign.sign_symbols)) []

(** [of_file f] computes statistics on rules of file [f]. *)
let of_file : string -> t = fun fname ->
  let mp = Files.module_path fname in
  begin let module C = Console in
    try compile mp
    with C.Fatal(None,    msg) -> C.exit_with "%s" msg
       | C.Fatal(Some(p), msg) -> C.exit_with "[%a] %s" Pos.print p msg end ;
  let sign = Files.PathMap.find mp Sign.(Timed.(!loaded)) in
  { fname = Some(fname)
  ; sym = count_symbols sign
  ; rul = count_rules sign
  ; nlr = count_nlrules sign
  ; hor = count_horules sign
  ; ari = rules_arity sign
  ; siz = rules_sizes sign
  ; hgt = rules_heights sign }

(** [merge d e] merges datasets [d] and [e] into one. *)
let merge : t -> t -> t = fun d e ->
  { fname = None
  ; sym = d.sym + e.sym
  ; rul = d.rul + e.rul
  ; nlr = d.nlr + e.nlr
  ; hor = d.hor + e.hor
  ; ari = D.merge d.ari e.ari
  ; siz = D.merge d.siz e.siz
  ; hgt = D.merge d.hgt e.hgt }

(** [pp f d] pretty prints data [d] to formatter [f]. *)
let pp : Format.formatter -> t -> unit = fun fmt d ->
  let module F = Format in
  F.fprintf fmt "SUMMARY:\n" ;
  F.fprintf fmt "@[<v 2>" ;
  begin match d.fname with
  | Some(n) -> F.fprintf fmt "File: %s@," n
  | None    -> () end ;
  F.fprintf fmt "Symbols: %d@," d.sym ;
  F.fprintf fmt "Rules: %d@," d.rul ;
  F.fprintf fmt "Non linear rules: %d@," d.nlr ;
  F.fprintf fmt "HO rules: %d@," d.hor

(** [csv_hdr f] outputs a csv header to formatter [f]. *)
let csv_hdr : Format.formatter -> unit = fun fmt ->
  Format.fprintf fmt "%s" ""

(** [pp_csv f d] outputs a line in csv format containing some of the
    information in a dataset. *)
let pp_csv : Format.formatter -> t -> unit = fun fmt ->
  let module F = Format in
  csv_hdr fmt ;
  assert false
