module X64.Memory
open Interop.Base
module IB = Interop.Base
module I = Interop
module HS = FStar.HyperStack
module HST = FStar.HyperStack.ST
module MB = LowStar.Monotonic.Buffer
module M = LowStar.Modifies
open LowStar.ModifiesPat
module BV = LowStar.BufferView
module H = FStar.Heap
module S = X64.Bytes_Semantics_s

#reset-options "--initial_fuel 2 --max_fuel 2 --initial_ifuel 1 --max_ifuel 1"

let b8 = IB.b8

let heap = H.heap
type mem = IB.mem

let op_String_Access = Map.sel
let op_String_Assignment = Map.upd

let coerce (#a:Type0) (b:Type0{a == b}) (x:a) : b = x

let tuint8 = UInt8.t
let tuint16 = UInt16.t
let tuint32 = UInt32.t
let tuint64 = UInt64.t

let v_of_typ (t:base_typ) (v:base_typ_as_vale_type t) : base_typ_as_type t =
  match t with
  | TUInt8 -> UInt8.uint_to_t v
  | TUInt16 -> UInt16.uint_to_t v
  | TUInt32 -> UInt32.uint_to_t v
  | TUInt64 -> UInt64.uint_to_t v
  | TUInt128 -> v

let v_to_typ (t:base_typ) (v:base_typ_as_type t) : base_typ_as_vale_type t =
  match t with
  | TUInt8 -> UInt8.v v
  | TUInt16 -> UInt16.v v
  | TUInt32 -> UInt32.v v
  | TUInt64 -> UInt64.v v
  | TUInt128 -> v

let lemma_v_to_of_typ (t:base_typ) (v:base_typ_as_vale_type t) : Lemma
  (ensures v_to_typ t (v_of_typ t v) == v)
  [SMTPat (v_to_typ t (v_of_typ t v))]
  = ()

let uint8_view = Views.view8
let uint16_view = Views.view16
let uint32_view = Views.view32
let uint64_view = Views.view64
let uint128_view = Views.view128

val uint_view (t:base_typ) : (v:BV.view UInt8.t (IB.base_typ_as_type t){BV.View?.n v == view_n t})

let uint_view = function
  | TUInt8 -> uint8_view
  | TUInt16 -> uint16_view
  | TUInt32 -> uint32_view
  | TUInt64 -> uint64_view
  | TUInt128 -> uint128_view

let buffer t = (b:b8{MB.length b.b % view_n t == 0})

let buffer_as_seq #t h b =
  let s = BV.as_seq (IB.hs_of_mem h) (BV.mk_buffer_view b.b (uint_view t)) in
  let len = Seq.length s in
  let contents (i:nat{i < len}) : base_typ_as_vale_type t = v_to_typ t (Seq.index s i) in
  Seq.init len contents

let buffer_readable #t h b = List.memP b (IB.ptrs_of_mem h)
let buffer_writeable #t b = b.writeable
let buffer_length #t b = BV.length (BV.mk_buffer_view b.b (uint_view t))
let loc = M.loc
let loc_none = M.loc_none
let loc_union = M.loc_union
let loc_buffer #t b = M.loc_buffer b.b
let loc_disjoint = M.loc_disjoint
let loc_includes = M.loc_includes
let modifies s h h' = 
  M.modifies s h.hs h'.hs /\ 
  h.ptrs == h'.ptrs /\ 
  h.addrs == h'.addrs /\
  HST.equal_domains h.hs h'.hs

let buffer_addr #t b h = IB.addrs_of_mem h b
open FStar.Mul
val index64_get_heap_val64 (h:mem)
                           (b:buffer64{List.memP b h.ptrs})
                           (heap:S.heap{IB.correct_down h heap})
                           (i:nat{i < buffer_length b})
   : Lemma (Seq.index (buffer_as_seq h b) i ==
            S.get_heap_val64 (buffer_addr b h + 8 * i) heap)

#set-options "--z3rlimit 20"

let index64_heap_aux (s:Seq.lseq UInt8.t 8) (heap:S.heap) (ptr:int) : Lemma
  (requires forall (j:nat{j < 8}). UInt8.v (Seq.index s j) == heap.[ptr+j])
  (ensures UInt64.v (Views.get64 s) == S.get_heap_val64 ptr heap) =
  Opaque_s.reveal_opaque Views.get64_def;
  Opaque_s.reveal_opaque S.get_heap_val64_def;
  Opaque_s.reveal_opaque Types_s.le_bytes_to_nat64_def

let index_helper (x y:int) (heap:S.heap) : Lemma
  (requires x == y)
  (ensures heap.[x] == heap.[y]) = ()

let index_mul_helper (addr i n j:int) : Lemma
  (addr + (i * n + j) == addr + n * i + j) =
 ()

#set-options "--max_fuel 0 --max_ifuel 0"

let index64_get_heap_val64 h b heap i =
  let open FStar.Mul in
  let vb = BV.mk_buffer_view b.b uint64_view in
  let ptr = buffer_addr b h + 8 * i in
  let s = MB.as_seq h.hs b.b in
  let t = TUInt64 in
  let addr = buffer_addr b h in
  BV.length_eq vb;
  BV.view_indexing vb i;
  BV.as_buffer_mk_buffer_view b.b uint64_view;
  BV.get_view_mk_buffer_view b.b uint64_view;
  BV.as_seq_sel h.hs vb i;
  BV.get_sel h.hs vb i;
  let s' = Seq.slice s (i*8) (i*8 + 8) in
  let aux (j:nat{j < 8}) : Lemma (UInt8.v (Seq.index s' j) == heap.[ptr+j]) =
    assert (UInt8.v (Seq.index s (i*8 + j)) == heap.[addr + (i*8+j)]);
    Seq.lemma_index_slice s (i*8) (i*8+8) j;
    assert (UInt8.v (Seq.index s' j) == heap.[addr+(i*8+j)]);
    index_mul_helper addr i 8 j;
    ()
  in Classical.forall_intro aux;
  index64_heap_aux s' heap ptr;
  ()

open Words_s

val index128_get_heap_val128 (h:mem)
                           (b:buffer128{List.memP b h.ptrs})
                           (heap:S.heap{IB.correct_down h heap})
                           (i:nat{i < buffer_length b}) : Lemma
(let addr = buffer_addr b h in
 Seq.index (buffer_as_seq h b) i ==
  Mkfour
    (S.get_heap_val32 (addr + 16 * i) heap)
    (S.get_heap_val32 (addr + 16 * i+4) heap)
    (S.get_heap_val32 (addr + 16 * i+8) heap)
    (S.get_heap_val32 (addr + 16 * i +12) heap)
 )

#set-options "--z3rlimit 50"

open Types_s
open Words.Seq_s
open Words.Four_s
open Collections.Seqs_s

let index128_get_heap_val128_aux (s:Seq.lseq UInt8.t 16) (ptr:int) (heap:S.heap) : Lemma
  (requires (forall (j:nat) . j < 16 ==> UInt8.v (Seq.index s j) == heap.[ptr+j]))
  (ensures Views.get128 s == Mkfour
    (S.get_heap_val32 ptr heap)
    (S.get_heap_val32 (ptr+4) heap)
    (S.get_heap_val32 (ptr+8) heap)
    (S.get_heap_val32 (ptr+12) heap)) =
  Opaque_s.reveal_opaque S.get_heap_val32_def;
  Opaque_s.reveal_opaque Views.get128_def;
  Opaque_s.reveal_opaque Types_s.le_bytes_to_quad32_def


let index128_get_heap_val128 h b heap i =
  let open FStar.Mul in
  let vb = BV.mk_buffer_view b.b uint128_view in
  let ptr = buffer_addr b h + 16 * i in
  let s = MB.as_seq h.hs b.b in
  let addr = buffer_addr b h in
  BV.length_eq vb;
  BV.view_indexing vb i;
  BV.as_buffer_mk_buffer_view b.b uint128_view;
  BV.get_view_mk_buffer_view b.b uint128_view;
  BV.as_seq_sel h.hs vb i;
  BV.get_sel h.hs vb i;
  let sv = Seq.index (buffer_as_seq h b) i in
  let sl = Seq.slice s (i*16) (i*16+16) in
  assert (sv == Views.get128 sl);
  let aux (j:nat{j < 16}) : Lemma (UInt8.v (Seq.index sl j) == heap.[ptr+j]) =
    assert (UInt8.v (Seq.index s (i*16 + j)) == heap.[addr + (i*16+j)]);
    Seq.lemma_index_slice s (i*16) (i*16+16) j;
    assert (UInt8.v (Seq.index sl j) == heap.[addr+(i*16+j)]);
    index_mul_helper addr i 16 j;
    ()
  in Classical.forall_intro aux;
  index128_get_heap_val128_aux sl ptr heap;
  ()

let modifies_goal_directed s h1 h2 = modifies s h1 h2
let lemma_modifies_goal_directed s h1 h2 = ()

let buffer_length_buffer_as_seq #t h b = ()

val same_underlying_seq (#t:base_typ) (h1 h2:mem) (b:buffer t) : Lemma
  (requires Seq.equal (MB.as_seq h1.hs b.b) (MB.as_seq h2.hs b.b))
  (ensures Seq.equal (buffer_as_seq h1 b) (buffer_as_seq h2 b))

let same_underlying_seq #t h1 h2 b =
  let rec aux (i:nat{i <= buffer_length b}) : Lemma
    (requires (forall (j:nat{j < i}). Seq.index (buffer_as_seq h1 b) j == Seq.index (buffer_as_seq h2 b) j) /\
    (Seq.equal (MB.as_seq h1.hs b.b) (MB.as_seq h2.hs b.b)))
    (ensures (forall (j:nat{j < buffer_length b}). Seq.index (buffer_as_seq h1 b) j == Seq.index (buffer_as_seq h2 b) j))
    (decreases %[(buffer_length b) - i]) =
    if i = buffer_length b then ()
    else (
      let bv = BV.mk_buffer_view b.b (uint_view t) in
      BV.as_buffer_mk_buffer_view b.b (uint_view t);
      BV.get_view_mk_buffer_view b.b (uint_view t);
      BV.get_sel h1.hs bv i;
      BV.get_sel h2.hs bv i;
      BV.as_seq_sel h1.hs bv i;
      BV.as_seq_sel h2.hs bv i;
      aux (i+1)
    )
  in aux 0

let modifies_buffer_elim #t1 b p h h' =
  M.modifies_buffer_elim b.b p h.hs h'.hs;
  assert (Seq.equal (MB.as_seq h.hs b.b) (MB.as_seq h'.hs b.b));
  same_underlying_seq h h' b;
  assert (Seq.equal (buffer_as_seq h b) (buffer_as_seq h' b));
  ()

let modifies_buffer_addr #t b p h h' = ()
let modifies_buffer_readable #t b p h h' = ()

let loc_disjoint_none_r s = M.loc_disjoint_none_r s
let loc_disjoint_union_r s s1 s2 = M.loc_disjoint_union_r s s1 s2
let loc_includes_refl s = M.loc_includes_refl s
let loc_includes_trans s1 s2 s3 = M.loc_includes_trans s1 s2 s3
let loc_includes_union_r s s1 s2 = M.loc_includes_union_r s s1 s2
let loc_includes_union_l s1 s2 s = M.loc_includes_union_l s1 s2 s
let loc_includes_union_l_buffer #t s1 s2 b = M.loc_includes_union_l s1 s2 (loc_buffer b)
let loc_includes_none s = M.loc_includes_none s
let modifies_refl s h = M.modifies_refl s h.hs
let modifies_goal_directed_refl s h = M.modifies_refl s h.hs
let modifies_loc_includes s1 h h' s2 = M.modifies_loc_includes s1 h.hs h'.hs s2
let modifies_trans s12 h1 h2 s23 h3 = M.modifies_trans s12 h1.hs h2.hs s23 h3.hs

let modifies_goal_directed_trans s12 h1 h2 s13 h3 =
  modifies_trans s12 h1 h2 s13 h3;
  modifies_loc_includes s13 h1 h3 (loc_union s12 s13);
  ()

let modifies_goal_directed_trans2 s12 h1 h2 s13 h3 = modifies_goal_directed_trans s12 h1 h2 s13 h3

let default_of_typ (t:base_typ) : base_typ_as_vale_type t =
  allow_inversion base_typ;
  match t with
  | TUInt8 -> 0
  | TUInt16 -> 0
  | TUInt32 -> 0
  | TUInt64 -> 0
  | TUInt128 -> Words_s.Mkfour #nat32 0 0 0 0

let buffer_read #t b i h =
  if i < 0 || i >= buffer_length b then default_of_typ t else
  Seq.index (buffer_as_seq h b) i

val seq_upd (#b:_)
            (h:HS.mem)
            (vb:BV.buffer b{BV.live h vb})
            (i:nat{i < BV.length vb})
            (x:b)
  : Lemma (Seq.equal
      (Seq.upd (BV.as_seq h vb) i x)
      (BV.as_seq (BV.upd h vb i x) vb))

let seq_upd #b h vb i x =
  let old_s = BV.as_seq h vb in
  let new_s = BV.as_seq (BV.upd h vb i x) vb in
  let upd_s = Seq.upd old_s i x in
  let rec aux (k:nat) : Lemma
    (requires (k <= Seq.length upd_s /\ (forall (j:nat). j < k ==> Seq.index upd_s j == Seq.index new_s j)))
    (ensures (forall (j:nat). j < Seq.length upd_s ==> Seq.index upd_s j == Seq.index new_s j))
    (decreases %[(Seq.length upd_s) - k]) =
    if k = Seq.length upd_s then ()
    else begin
      BV.sel_upd vb i k x h;
      BV.as_seq_sel h vb k;
      BV.as_seq_sel (BV.upd h vb i x) vb k;
      aux (k+1)
    end
  in aux 0;
  ()

let buffer_write #t b i v h =
 if i < 0 || i >= buffer_length b then h else
 begin
   let view = uint_view t in
   let bv = BV.mk_buffer_view b.b view in
   BV.as_buffer_mk_buffer_view b.b view;
   BV.upd_modifies h.hs bv i (v_of_typ t v);
   BV.upd_equal_domains h.hs bv i (v_of_typ t v);
   let hs' = BV.upd h.hs bv i (v_of_typ t v) in
   let h':mem = Mem h.ptrs h.addrs hs' in
   seq_upd h.hs bv i (v_of_typ t v);
   assert (Seq.equal (buffer_as_seq h' b) (Seq.upd (buffer_as_seq h b) i v));
   h'
 end

val addr_in_ptr: (#t:base_typ) -> (addr:int) -> (ptr:buffer t) -> (h:mem) ->
  GTot (b:bool{ not b <==> (forall i. 0 <= i /\ i < buffer_length ptr ==>
    addr <> (buffer_addr ptr h) + (view_n t) * i)})

// Checks if address addr corresponds to one of the elements of buffer ptr
let addr_in_ptr #t addr ptr h =
  let n = buffer_length ptr in
  let base = buffer_addr ptr h in
  let rec aux (i:nat) : Tot (b:bool{not b <==> (forall j. i <= j /\ j < n ==>
    addr <> base + (view_n t) * j)})
    (decreases %[n-i]) =
    if i >= n then false
    else if addr = base + (view_n t) * i then true
    else aux (i+1)
  in aux 0

let valid_offset (t:base_typ) (n base:nat) (addr:int) (i:nat) = exists j. i <= j /\ j < n /\ base + (view_n t) * j == addr

let rec get_addr_in_ptr (t:base_typ) (n base addr:nat) (i:nat{valid_offset t n base addr i})
  : GTot (j:nat{base + (view_n t) * j == addr})
    (decreases %[n-i]) =
    if base + (view_n t) * i = addr then i
    else get_addr_in_ptr t n base addr (i+1)

let valid_buffer (t:base_typ) (addr:int) (b:b8) (h:mem) : GTot bool =
  MB.length b.b % (view_n t) = 0 &&
  addr_in_ptr #t addr b h

let writeable_buffer (t:base_typ) (addr:int) (b:b8) (h:mem) : GTot bool =
  valid_buffer t addr b h && b.writeable

#set-options "--max_fuel 1 --max_ifuel 1"
let sub_list (p1 p2:list 'a) = forall x. {:pattern List.memP x p2} List.memP x p1 ==> List.memP x p2

let rec valid_mem_aux (t:base_typ) addr (ps:list b8) (h:mem {sub_list ps h.ptrs})
  : GTot (b:bool{
           b <==>
           (exists (x:buffer t). {:pattern (List.memP x ps) \/ (valid_buffer t addr x h)}
             List.memP x ps /\ valid_buffer t addr x h)})
  = match ps with
    | [] -> false
    | a::q -> valid_buffer t addr a h || valid_mem_aux t addr q h
let valid_mem (t:base_typ) addr (h:mem) = valid_mem_aux t addr h.ptrs h
let valid_mem64 ptr h = valid_mem (TUInt64) ptr h

let rec find_valid_buffer_aux (t:base_typ) (addr:int) (ps:list b8) (h:mem{sub_list ps h.ptrs})
  : GTot (o:option (buffer t){
    match o with
    | None -> not (valid_mem_aux t addr ps h)
    | Some a -> valid_buffer t addr a h /\ List.memP a ps})
  = match ps with
    | [] -> None
    | a::q -> if valid_buffer t addr a h then Some a else find_valid_buffer_aux t addr q h
    
let find_valid_buffer (t:base_typ) (addr:int) (h:mem) = find_valid_buffer_aux t addr h.ptrs h

let rec find_valid_buffer_aux_ps (t:base_typ) (addr:int) (ps:list b8) (h1:mem) (h2:mem{h1.ptrs == h2.ptrs /\ sub_list ps h1.ptrs})
  : Lemma (find_valid_buffer_aux t addr ps h1 == find_valid_buffer_aux t addr ps h2)
  = match ps with
    | [] -> ()
    | a::q -> find_valid_buffer_aux_ps t addr q h1 h2

let find_valid_buffer_ps (t:base_typ) (addr:int) (h1:mem) (h2:mem{h1.ptrs==h2.ptrs})
  : Lemma (find_valid_buffer t addr h1 == find_valid_buffer t addr h2)
  = find_valid_buffer_aux_ps t addr h1.ptrs h1 h2

let find_valid_buffer_valid_offset (t:base_typ) (addr:int) (h:mem)
  : Lemma (match find_valid_buffer t addr h with
           | None -> True
           | Some a ->
             let base = buffer_addr a h in
             valid_offset t (buffer_length a) base addr 0)
  = ()

let rec writeable_mem_aux (t:base_typ) addr (ps:list b8) (h:mem {sub_list ps h.ptrs})
  : GTot (b:bool{
           b <==>
           (exists (x:buffer t). {:pattern (List.memP x ps) \/ (valid_buffer t addr x h) \/ buffer_writeable x}
             List.memP x ps /\ valid_buffer t addr x h /\ buffer_writeable x)})
  = match ps with
    | [] -> false
    | a::q -> writeable_buffer t addr a h || writeable_mem_aux t addr q h
let writeable_mem (t:base_typ) addr (h:mem) = writeable_mem_aux t addr h.ptrs h
let writeable_mem64 ptr h = writeable_mem (TUInt64) ptr h

let rec find_writeable_buffer_aux (t:base_typ) (addr:int) (ps:list b8) (h:mem{sub_list ps h.ptrs})
  : GTot (o:option (buffer t){
    match o with
    | None -> not (writeable_mem_aux t addr ps h)
    | Some a -> writeable_buffer t addr a h /\ List.memP a ps})
  = match ps with
    | [] -> None
    | a::q -> if writeable_buffer t addr a h then Some a else find_writeable_buffer_aux t addr q h
    
let find_writeable_buffer (t:base_typ) (addr:int) (h:mem) = find_writeable_buffer_aux t addr h.ptrs h

let load_mem (t:base_typ) addr (h:mem)
  : GTot (base_typ_as_vale_type t) =
  match find_valid_buffer t addr h with
  | None -> default_of_typ t
  | Some a ->
    let base = buffer_addr a h in
    buffer_read a (get_addr_in_ptr t (buffer_length a) base addr 0) h

let load_mem64 ptr h =
  if not (valid_mem64 ptr h) then 0
  else load_mem (TUInt64) ptr h

let length_t_eq (t:base_typ) (b:buffer t) : Lemma (MB.length b.b == buffer_length b * (view_n t)) =
  BV.as_buffer_mk_buffer_view b.b (uint_view t);
  BV.get_view_mk_buffer_view b.b (uint_view t);
  BV.length_eq (BV.mk_buffer_view b.b (uint_view t))

let get_addr_ptr (t:base_typ) (ptr:int) (h:mem{valid_mem t ptr h})
  : GTot (b:buffer t{List.memP b h.ptrs /\ valid_buffer t ptr b h})
  = Some?.v (find_valid_buffer t ptr h)

#reset-options "--max_fuel 0 --max_ifuel 0 --initial_fuel 0 --initial_ifuel 0"
val load_buffer_read
          (t:base_typ)
          (ptr:int)
          (h:mem{valid_mem t ptr h})
 : Lemma
    (ensures (let b = get_addr_ptr t ptr h in
              let i = get_addr_in_ptr t (buffer_length b) (buffer_addr b h) ptr 0 in
              load_mem t ptr h == buffer_read #t b i h))
let load_buffer_read t ptr h = ()

let store_mem (t:base_typ) addr (v:base_typ_as_vale_type t) (h:mem)
  : GTot (h1:mem{h.addrs == h1.addrs /\ h.ptrs == h1.ptrs })
  = match find_writeable_buffer t addr h with
    | None -> h
    | Some a ->
      let base = buffer_addr a h in
      buffer_write a (get_addr_in_ptr t (buffer_length a) base addr 0) v h

let store_mem64 i v h =
  if not (valid_mem64 i h) then h
  else store_mem (TUInt64) i v h

val store_buffer_write
          (t:base_typ)
          (ptr:int)
          (v:base_typ_as_vale_type t)
          (h:mem{writeable_mem t ptr h})
  : Lemma
      (let b = Some?.v (find_writeable_buffer t ptr h) in
       let i = get_addr_in_ptr t (buffer_length b) (buffer_addr b h) ptr 0 in
       store_mem t ptr v h == buffer_write b i v h)
let store_buffer_write t ptr v h = ()

let valid_mem128 ptr h = valid_mem_aux (TUInt128) ptr h.ptrs h
let writeable_mem128 ptr h = writeable_mem_aux (TUInt128) ptr h.ptrs h
let load_mem128 ptr h =
  if not (valid_mem128 ptr h) then (default_of_typ (TUInt128))
  else load_mem (TUInt128) ptr h
let store_mem128 ptr v h =
  if not (valid_mem128 ptr h) then h
  else store_mem (TUInt128) ptr v h

let lemma_valid_mem64 b i h = ()
let lemma_writeable_mem64 b i h = ()

let lemma_load_mem64 b i h =
  let addr = buffer_addr b h + 8 * i in
  lemma_valid_mem64 b i h;
  match find_valid_buffer TUInt64 addr h with
  | None -> ()
  | Some a ->
    BV.length_eq (BV.mk_buffer_view a.b uint64_view);
    BV.get_view_mk_buffer_view a.b uint64_view;
    BV.as_buffer_mk_buffer_view a.b uint64_view;
    BV.length_eq (BV.mk_buffer_view b.b uint64_view);
    BV.get_view_mk_buffer_view b.b uint64_view;
    BV.as_buffer_mk_buffer_view b.b uint64_view;
    assert (IB.disjoint_or_eq_b8 a b);
    assert (a == b)

val lemma_store_mem : t:base_typ -> b:buffer t -> i:nat-> v:base_typ_as_vale_type t -> h:mem -> Lemma
  (requires
    i < Seq.length (buffer_as_seq h b) /\
    buffer_readable h b /\
    buffer_writeable b
  )
  (ensures
    store_mem t (buffer_addr b h + view_n t `op_Multiply` i) v h == buffer_write b i v h
  )

let lemma_store_mem t b i v h =
  let view = uint_view t in
  let addr = buffer_addr b h + view_n t * i in
  match find_writeable_buffer t addr h with
  | None -> ()
  | Some a ->
    BV.length_eq (BV.mk_buffer_view a.b view);
    BV.get_view_mk_buffer_view a.b view;
    BV.as_buffer_mk_buffer_view a.b view;
    BV.length_eq (BV.mk_buffer_view b.b view);
    BV.get_view_mk_buffer_view b.b view;
    BV.as_buffer_mk_buffer_view b.b view;
    assert (IB.disjoint_or_eq_b8 a b);
    assert (a == b)

let lemma_store_mem64 b i v h = lemma_store_mem TUInt64 b i v h

let lemma_valid_mem128 b i h = ()
let lemma_writeable_mem128 b i h = ()

let lemma_load_mem128 b i h =
  let addr = buffer_addr b h + 16 * i in
  lemma_valid_mem128 b i h;
  match find_valid_buffer TUInt128 addr h with
  | None -> ()
  | Some a ->
    BV.length_eq (BV.mk_buffer_view a.b uint128_view);
    BV.get_view_mk_buffer_view a.b uint128_view;
    BV.as_buffer_mk_buffer_view a.b uint128_view;
    BV.length_eq (BV.mk_buffer_view b.b uint128_view);
    BV.get_view_mk_buffer_view b.b uint128_view;
    BV.as_buffer_mk_buffer_view b.b uint128_view;
    assert (IB.disjoint_or_eq_b8 a b);
    assert (a == b)

let lemma_store_mem128 b i v h = lemma_store_mem TUInt128 b i v h

open X64.Machine_s

let valid_taint_buf (b:b8) (mem:mem) (memTaint:memtaint) t =
  let addr = mem.addrs b in
  (forall (i:nat{i < MB.length b.b}).{:pattern (memTaint.[addr + i])} memTaint.[addr + i] = t)

let valid_taint_buf64 b mem memTaint t = valid_taint_buf b mem memTaint t

let valid_taint_buf128 b mem memTaint t = valid_taint_buf b mem memTaint t

let apply_taint_buf (b:b8) (mem:mem) (memTaint:memtaint) (t:taint) (i:nat) : Lemma
  (requires i < MB.length b.b /\ valid_taint_buf b mem memTaint t)
  (ensures memTaint.[mem.addrs b + i] = t) = ()

let lemma_valid_taint64 b memTaint mem i t =
  length_t_eq (TUInt64) b;
  let ptr = buffer_addr b mem + 8 * i in
  let aux (i':nat) : Lemma
    (requires i' >= ptr /\ i' < ptr + 8)
    (ensures memTaint.[i'] == t) =
    let extra = 8 * i + i' - ptr in
    assert (i' == mem.addrs b + extra);
    apply_taint_buf b mem memTaint t extra
  in
  Classical.forall_intro (Classical.move_requires aux)

let lemma_valid_taint128 b memTaint mem i t =
  length_t_eq (TUInt128) b;
  let ptr = buffer_addr b mem + 16 * i in
  let aux i' : Lemma
    (requires i' >= ptr /\ i' < ptr + 16)
    (ensures memTaint.[i'] == t) =
    let extra = 16 * i + i' - ptr in
    assert (i' == mem.addrs b + extra);
    apply_taint_buf b mem memTaint t extra
  in
  Classical.forall_intro (Classical.move_requires aux)

let same_memTaint (t:base_typ) (b:buffer t) (mem0 mem1:mem) (memT0 memT1:memtaint) : Lemma
  (requires modifies (loc_buffer b) mem0 mem1 /\
    (forall p. Map.sel memT0 p == Map.sel memT1 p))
  (ensures memT0 == memT1) =
  assert (Map.equal memT0 memT1)

let same_memTaint64 b mem0 mem1 memtaint0 memtaint1 =
  same_memTaint (TUInt64) b mem0 mem1 memtaint0 memtaint1

let same_memTaint128 b mem0 mem1 memtaint0 memtaint1 =
  same_memTaint (TUInt128) b mem0 mem1 memtaint0 memtaint1

let modifies_valid_taint64 b p h h' memTaint t = ()
let modifies_valid_taint128 b p h h' memTaint t = ()

let valid_taint_bufs (mem:mem) (memTaint:memtaint) (ps:list b8) (ts:b8 -> GTot taint) =
  forall b.{:pattern List.memP b ps} List.memP b ps ==> valid_taint_buf b mem memTaint (ts b)

#set-options "--initial_fuel 1 --max_fuel 1 --initial_ifuel 1 --max_ifuel 1"
let rec write_taint_lemma (i:nat) (mem:IB.mem) (ts:b8 -> GTot taint) (b:b8{i <= MB.length b.b})
                          (accu:memtaint{forall j. 0 <= j /\ j < i ==> accu.[mem.addrs b+j] = ts b})
   : Lemma
       (ensures (
         let m = IB.write_taint i mem ts b accu in
         let addr = mem.addrs b in
         (forall j. {:pattern m.[addr+j]} 0 <= j /\ j < MB.length b.b ==> m.[addr+j] = ts b) /\
         (forall j. {:pattern m.[j]} j < addr \/ j >= addr + MB.length b.b ==> m.[j] == accu.[j])))
       (decreases %[MB.length b.b - i])
   = let m = IB.write_taint i mem ts b accu in
     let addr = mem.addrs b in
     if i >= MB.length b.b then ()
     else let new_accu = accu.[addr+i] <- ts b in
          assert (IB.write_taint i mem ts b accu ==
                  IB.write_taint (i + 1) mem ts b new_accu);
          assert (Set.equal (Map.domain new_accu) (Set.complement Set.empty));
          assert (forall j. 0 <= j /\ j < i + 1 ==> new_accu.[addr + i] == ts b);
          write_taint_lemma (i + 1) mem ts b new_accu

let rec valid_memtaint (mem:mem) (ps:list b8{IB.list_disjoint_or_eq ps}) (ts:b8 -> GTot taint)
  : Lemma (valid_taint_bufs mem (IB.create_memtaint mem ps ts) ps ts)
  = match ps with
    | [] -> ()
    | b :: q ->
      assert (List.memP b ps);
      assert (forall i. {:pattern List.memP i q} List.memP i q ==> List.memP i ps);
      assert (IB.list_disjoint_or_eq q);
      valid_memtaint mem q ts;
      assert (IB.create_memtaint mem ps ts ==
              IB.write_taint 0 mem ts b (IB.create_memtaint mem q ts));
      write_taint_lemma 0 mem ts b (IB.create_memtaint mem q ts);
      assert (forall p. List.memP p q ==> IB.disjoint_or_eq_b8 p b)
