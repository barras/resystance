open Core
module F = Format
module U = Unification

(** [sig_of_file f] returns the signature of the file path [f]. *)
let sig_of_file : string -> Sign.t = fun fname ->
  let mp = Files.module_path fname in
  let module C = Console in
  begin try Compile.compile true mp
    with C.Fatal(None, msg) -> C.exit_with "%s" msg
       | C.Fatal(Some(p), msg) -> C.exit_with "[%a] %s" Pos.print p msg end;
  Files.PathMap.find mp Sign.(Timed.(!loaded))

let spec =
  Arg.align []
let _ =
  let usage = Printf.sprintf "Usage: %s [OPTIONS] [FILES]" Sys.argv.(0) in
  let files = ref [] in
  Arg.parse spec (fun s -> files := s :: !files) usage;
  files := List.rev !files;
  let sigs = List.map sig_of_file !files in
  let cps = List.map Critical_pairs.cps sigs in
  let ppf = F.std_formatter in
  let pp_quadruple_s fmt (l1, l2, lr, s) =
    F.fprintf fmt "[%a] =? [%a] -> [%a] {%a}"
      Print.pp l1 Print.pp l2 Print.pp lr U.pp_subst s
  in
  let pp_sig_cp fmt scps =
    F.pp_print_list ~pp_sep:(F.pp_print_newline) pp_quadruple_s fmt scps
  in
  let pp_sep fmt () = F.fprintf fmt "\n%%%%\n" in
  F.pp_print_list ~pp_sep pp_sig_cp ppf cps;
  Format.fprintf ppf "\n"
