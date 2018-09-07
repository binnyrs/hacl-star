module Hacl.Impl.Matrix

open FStar.HyperStack.ST
open FStar.Mul

open LowStar.BufferOps
open LowStar.Buffer

open Lib.IntTypes
open Lib.PQ.Buffer
open Lib.Endianness

module B   = LowStar.Buffer
module HS  = FStar.HyperStack
module ST  = FStar.HyperStack.ST
module Seq = Lib.Sequence
module M   = Spec.Matrix
module Lemmas = Spec.Frodo.Lemmas

#reset-options "--z3rlimit 50 --max_fuel 0 --max_ifuel 0"

unfold
type elem = uint16

inline_for_extraction
let lbytes len = lbuffer uint8 (v len)

inline_for_extraction noextract unfold
let v = size_v

type matrix_t (n1:size_t) (n2:size_t{v n1 * v n2 <= max_size_t}) =
  lbuffer elem (v n1 * v n2)

/// It's important to mark it as [unfold] for triggering patterns in [LowStar]
unfold
let as_matrix #n1 #n2 h (m:matrix_t n1 n2) : GTot (M.matrix (v n1) (v n2)) =
  B.as_seq h m

inline_for_extraction noextract
val matrix_create:
    n1:size_t
  -> n2:size_t{0 < v n1 * v n2 /\ v n1 * v n2 <= max_size_t}
  -> StackInline (matrix_t n1 n2)
    (requires fun h0 -> True)
    (ensures  fun h0 a h1 ->
      B.alloc_post_mem_common a h0 h1 (as_matrix h1 a) /\
      as_matrix h1 a == M.create (v n1) (v n2))
let matrix_create n1 n2 =
  [@inline_let]
  let len = size (normalize_term (v n1 * v n2)) in
  create len (u16 0)

inline_for_extraction noextract
val mget:
    #n1:size_t
  -> #n2:size_t{v n1 * v n2 <= max_size_t}
  -> a:matrix_t n1 n2
  -> i:size_t{v i < v n1}
  -> j:size_t{v j < v n2}
  -> Stack elem
    (requires fun h0 -> B.live h0 a)
    (ensures  fun h0 x h1 ->
      modifies loc_none h0 h1 /\
      x == M.mget (as_matrix h0 a) (v i) (v j))
let mget #n1 #n2 a i j =
  M.index_lt (v n1) (v n2) (v i) (v j);
  a.(i *. n2 +. j)

inline_for_extraction noextract
val mset:
    #n1:size_t
  -> #n2:size_t{v n1 * v n2 <= max_size_t}
  -> a:matrix_t n1 n2
  -> i:size_t{v i < v n1}
  -> j:size_t{v j < v n2}
  -> x:elem
  -> Stack unit
    (requires fun h0 -> B.live h0 a)
    (ensures  fun h0 _ h1 ->
      modifies (loc_buffer a) h0 h1 /\
      B.live h1 a /\
      as_matrix h1 a == M.mset (as_matrix h0 a) (v i) (v j) x)
let mset #n1 #n2 a i j x =
  M.index_lt (v n1) (v n2) (v i) (v j);
  a.(i *. n2 +. j) <- x

noextract unfold
let op_String_Access #n1 #n2 (m:matrix_t n1 n2) (i, j) = mget m i j

noextract unfold
let op_String_Assignment #n1 #n2 (m:matrix_t n1 n2) (i, j) x = mset m i j x

unfold
let get #n1 #n2 h (m:matrix_t n1 n2) i j = M.mget (as_matrix h m) i j

private unfold
val map2_inner_inv:
    #n1:size_t
  -> #n2:size_t{v n1 * v n2 <= max_size_t}
  -> h0:HS.mem
  -> h1:HS.mem
  -> h2:HS.mem
  -> f:(elem -> elem -> elem)
  -> a:matrix_t n1 n2
  -> b:matrix_t n1 n2
  -> c:matrix_t n1 n2
  -> i:size_t{v i < v n1}
  -> j:size_nat
  -> Type0
let map2_inner_inv #n1 #n2 h0 h1 h2 f a b c i j =
  B.live h2 a /\ B.live h2 b /\ B.live h2 c /\
  modifies (loc_buffer c) h1 h2 /\
  j <= v n2 /\
  (forall (i0:nat{i0 < v i}) (j:nat{j < v n2}). get h2 c i0 j == get h1 c i0 j) /\
  (forall (j0:nat{j0 < j}). get h2 c (v i) j0 == f (get h0 a (v i) j0) (get h2 b (v i) j0)) /\
  (forall (j0:nat{j <= j0 /\ j0 < v n2}). get h2 c (v i) j0 == get h0 c (v i) j0) /\
  (forall (i0:nat{v i < i0 /\ i0 < v n1}) (j:nat{j < v n2}). get h2 c i0 j == get h0 c i0 j)

inline_for_extraction noextract private
val map2_inner:
    #n1:size_t
  -> #n2:size_t{v n1 * v n2 <= max_size_t}
  -> h0:HS.mem
  -> h1:HS.mem
  -> f:(elem -> elem -> elem)
  -> a:matrix_t n1 n2
  -> b:matrix_t n1 n2
  -> c:matrix_t n1 n2{a == c /\ B.disjoint b c}
  -> i:size_t{v i < v n1}
  -> j:size_t{v j < v n2}
  -> Stack unit
    (requires fun h2 -> map2_inner_inv h0 h1 h2 f a b c i (v j))
    (ensures  fun _ _ h2 -> map2_inner_inv h0 h1 h2 f a b c i (v j + 1))
let map2_inner #n1 #n2 h0 h1 f a b c i j =
  c.[i,j] <- f a.[i,j] b.[i,j]

/// In-place [map2], a == map2 f a b
///
/// A non in-place variant can be obtained by weakening the pre-condition to B.disjoint a c,
/// or the two variants can be merged by requiring (a == c \/ B.disjoint a c) instead of a == c
/// See commit 91916b8372fa3522061eff5a42d0ebd1d19a8a49
inline_for_extraction
val map2:
    #n1:size_t
  -> #n2:size_t{v n1 * v n2 <= max_size_t}
  -> f:(uint16 -> uint16 -> uint16)
  -> a:matrix_t n1 n2
  -> b:matrix_t n1 n2
  -> c:matrix_t n1 n2
  -> Stack unit
    (requires fun h0 ->
      B.live h0 a /\ B.live h0 b /\ B.live h0 c /\ a == c /\ B.disjoint b c)
    (ensures  fun h0 _ h1 ->
      modifies (loc_buffer c) h0 h1 /\
      as_matrix h1 c == M.map2 #(v n1) #(v n2) f (as_matrix h0 a) (as_matrix h0 b))
let map2 #n1 #n2 f a b c =
  let h0 = ST.get () in
  Lib.Loops.for (size 0) n1
    (fun h1 i -> B.live h1 a /\ B.live h1 b /\ B.live h1 c /\
      modifies (loc_buffer c) h0 h1 /\ i <= v n1 /\
      (forall (i0:nat{i0 < i}) (j:nat{j < v n2}).
        get h1 c i0 j == f (get h0 a i0 j) (get h0 b i0 j)) /\
      (forall (i0:nat{i <= i0 /\ i0 < v n1}) (j:nat{j < v n2}).
        get h1 c i0 j == get h0 c i0 j) )
    (fun i ->
      let h1 = ST.get() in
      Lib.Loops.for (size 0) n2
        (fun h2 j -> map2_inner_inv h0 h1 h2 f a b c i j)
        (fun j -> map2_inner h0 h1 f a b c i j)
    );
    let h2 = ST.get() in
    M.extensionality (as_matrix h2 c) (M.map2 f (as_matrix h0 a) (as_matrix h0 b))

val matrix_add:
    #n1:size_t
  -> #n2:size_t{v n1 * v n2 <= max_size_t}
  -> a:matrix_t n1 n2
  -> b:matrix_t n1 n2
  -> Stack unit
    (requires fun h -> B.live h a /\ B.live h b /\ B.disjoint a b)
    (ensures  fun h0 r h1 -> B.live h1 a /\ modifies (loc_buffer a) h0 h1 /\
      as_matrix h1 a == M.add (as_matrix h0 a) (as_matrix h0 b))
[@"c_inline"]
let matrix_add #n1 #n2 a b =
  map2 add_mod a b a

val matrix_sub:
    #n1:size_t
  -> #n2:size_t{v n1 * v n2 <= max_size_t}
  -> a:matrix_t n1 n2
  -> b:matrix_t n1 n2
  -> Stack unit
    (requires fun h -> B.live h a /\ B.live h b /\ B.disjoint a b)
    (ensures  fun h0 r h1 -> B.live h1 b /\ modifies (loc_buffer b) h0 h1 /\
      as_matrix h1 b == M.sub (as_matrix h0 a) (as_matrix h0 b))
[@"c_inline"]
let matrix_sub #n1 #n2 a b =
  (* Use the in-place variant above by flipping the arguments of [sub_mod] *)
  (* Requires appplying extensionality *)
  let h0 = ST.get() in
  [@ inline_let ]
  let sub_mod_flipped x y = sub_mod y x in
  map2 sub_mod_flipped b a b;
  let h1 = ST.get() in
  M.extensionality (as_matrix h1 b) (M.sub (as_matrix h0 a) (as_matrix h0 b))

#reset-options "--z3rlimit 50 --max_fuel 1 --max_ifuel 0"

inline_for_extraction noextract private
val mul_inner:
    #n1:size_t
  -> #n2:size_t{v n1 * v n2 <= max_size_t}
  -> #n3:size_t{v n2 * v n3 <= max_size_t /\ v n1 * v n3 <= max_size_t}
  -> a:matrix_t n1 n2
  -> b:matrix_t n2 n3
  -> i:size_t{v i < v n1}
  -> k:size_t{v k < v n3}
  -> Stack uint16
    (requires fun h -> B.live h a /\ B.live h b)
    (ensures  fun h0 r h1 ->
      modifies loc_none h0 h1 /\
      r == M.mul_inner (as_matrix h0 a) (as_matrix h0 b) (v i) (v k))
let mul_inner #n1 #n2 #n3 a b i k =
  push_frame();
  let h0 = ST.get() in
  [@ inline_let ]
  let f l = get h0 a (v i) l *. get h0 b l (v k) in
  let res = create #uint16 #1 (size 1) (u16 0) in

  let h1 = ST.get() in
  Lib.Loops.for (size 0) n2
    (fun h2 j -> B.live h1 res /\ B.live h2 res /\
      modifies (loc_buffer res) h1 h2 /\
      B.get h2 res 0 == M.sum_ #(v n2) f j)
    (fun j ->
      let aij = a.[i,j] in
      let bjk = b.[j,k] in
      let res0 = res.(size 0) in
      res.(size 0) <- res0 +. aij *. bjk
    );
  let res = res.(size 0) in
  M.sum_extensionality (v n2) f (fun l -> get h0 a (v i) l *. get h0 b l (v k)) (v n2);
  assert (res == M.mul_inner (as_matrix h0 a) (as_matrix h0 b) (v i) (v k));
  pop_frame();
  res

#reset-options "--z3rlimit 50 --max_fuel 0 --max_ifuel 0"

private unfold
val mul_inner_inv:
    #n1:size_t
  -> #n2:size_t{v n1 * v n2 <= max_size_t}
  -> #n3:size_t{v n2 * v n3 <= max_size_t /\ v n1 * v n3 <= max_size_t}
  -> h0:HS.mem
  -> h1:HS.mem
  -> h2:HS.mem
  -> a:matrix_t n1 n2
  -> b:matrix_t n2 n3
  -> c:matrix_t n1 n3
  -> f:(k:nat{k < v n3} -> GTot uint16)
  -> i:size_t{v i < v n1}
  -> k:size_nat
  -> Type0
let mul_inner_inv #n1 #n2 #n3 h0 h1 h2 a b c f i k =
  B.live h2 a /\ B.live h2 b /\ B.live h2 c /\
  modifies (loc_buffer c) h1 h2 /\
  k <= v n3 /\
  (forall (i1:nat{i1 < v i}) (k:nat{k < v n3}). get h2 c i1 k == get h1 c i1 k) /\
  (forall (k1:nat{k1 < k}). get h2 c (v i) k1 == f k1) /\
  (forall (k1:nat{k <= k1 /\ k1 < v n3}). get h2 c (v i) k1 == get h0 c (v i) k1) /\
  (forall (i1:nat{v i < i1 /\ i1 < v n1}) (k:nat{k < v n3}). get h2 c i1 k == get h0 c i1 k) /\
  as_matrix h0 a == as_matrix h2 a /\
  as_matrix h0 b == as_matrix h2 b

inline_for_extraction noextract private
val mul_inner1:
    #n1:size_t
  -> #n2:size_t{v n1 * v n2 <= max_size_t}
  -> #n3:size_t{v n2 * v n3 <= max_size_t /\ v n1 * v n3 <= max_size_t}
  -> h0:HS.mem
  -> h1:HS.mem
  -> a:matrix_t n1 n2
  -> b:matrix_t n2 n3
  -> c:matrix_t n1 n3{B.disjoint a c /\ B.disjoint b c}
  -> i:size_t{v i < v n1}
  -> k:size_t{v k < v n3}
  -> f:(k:nat{k < v n3}
       -> GTot (res:uint16{res == M.sum #(v n2) (fun l -> get h0 a (v i) l *. get h0 b l k)}))
  -> Stack unit
    (requires fun h2 -> mul_inner_inv h0 h1 h2 a b c f i (v k))
    (ensures  fun _ _ h2 -> mul_inner_inv h0 h1 h2 a b c f i (v k + 1))
let mul_inner1 #n1 #n2 #n3 h0 h1 a b c i k f =
  assert (M.mul_inner (as_matrix h0 a) (as_matrix h0 b) (v i) (v k) ==
          M.sum #(v n2) (fun l -> get h0 a (v i) l *. get h0 b l (v k)));
  c.[i,k] <- mul_inner a b i k;
  let h2 = ST.get () in
  assert (get h2 c (v i) (v k) == f (v k))

private
val onemore: p:(nat -> Type0) -> q:(i:nat{p i} -> Type0) -> b:nat{p b} -> Lemma
  (requires (forall (i:nat{p i /\ i < b}). q i) /\ q b)
  (ensures  forall (i:nat{p i /\ i <= b}). q i)
let onemore p q b = ()

val matrix_mul:
    #n1:size_t
  -> #n2:size_t{v n1 * v n2 <= max_size_t}
  -> #n3:size_t{v n2 * v n3 <= max_size_t /\ v n1 * v n3 <= max_size_t}
  -> a:matrix_t n1 n2
  -> b:matrix_t n2 n3
  -> c:matrix_t n1 n3
  -> Stack unit
    (requires fun h ->
      B.live h a /\ B.live h b /\ B.live h c /\ B.disjoint a c /\ B.disjoint b c)
    (ensures  fun h0 _ h1 ->
      B.live h1 c /\
      modifies (loc_buffer c) h0 h1 /\
      as_matrix h1 c == M.mul (as_matrix h0 a) (as_matrix h0 b))
[@"c_inline"]
let matrix_mul #n1 #n2 #n3 a b c =
  let h0 = ST.get () in
  let f (i:nat{i < v n1}) (k:nat{k < v n3}) :
    GTot (res:uint16{res == M.sum #(v n2) (fun l -> get h0 a i l *. get h0 b l k)})
  = M.sum #(v n2) (fun l -> get h0 a i l *. get h0 b l k)
  in
  Lib.Loops.for (size 0) n1
    (fun h1 i ->
      B.live h1 a /\ B.live h1 b /\ B.live h1 c /\
      modifies (loc_buffer c) h0 h1 /\ i <= v n1 /\
      (forall (i1:nat{i1 < i}) (k:nat{k < v n3}). get h1 c i1 k == f i1 k) /\
      (forall (i1:nat{i <= i1 /\ i1 < v n1}) (k:nat{k < v n3}). get h1 c i1 k == get h0 c i1 k))
    (fun i ->
      let h1 = ST.get() in
      Lib.Loops.for (size 0) n3
        (fun h2 k -> mul_inner_inv h0 h1 h2 a b c (f (v i)) i k)
        (fun k -> mul_inner1 h0 h1 a b c i k (f (v i)));
      let h1 = ST.get() in
      let q i1 = forall k. get h1 c i1 k == f i1 k in
      onemore (fun i1 -> i1 < v n1) q (v i)
    );
  let h2 = ST.get() in
  M.extensionality (as_matrix h2 c) (M.mul (as_matrix h0 a) (as_matrix h0 b))

(* Special case of matrix multiplication *)
(* when we have a different way of accessing to entries of the matrix S *)

inline_for_extraction noextract
val mget_s:
    #n1:size_t
  -> #n2:size_t{v n1 * v n2 <= max_size_t}
  -> a:matrix_t n1 n2
  -> i:size_t{v i < v n1}
  -> j:size_t{v j < v n2}
  -> Stack elem
    (requires fun h0 -> B.live h0 a)
    (ensures  fun h0 x h1 ->
      modifies loc_none h0 h1 /\
      x == M.mget_s (as_matrix h0 a) (v i) (v j))
let mget_s #n1 #n2 a i j =
  M.index_lt_s (v n1) (v n2) (v i) (v j);
  a.(j *. n1 +. i)

unfold
let get_s #n1 #n2 h (m:matrix_t n1 n2) i j = M.mget_s (as_matrix h m) i j

#reset-options "--z3rlimit 50 --max_fuel 1 --max_ifuel 0"

inline_for_extraction noextract private
val mul_inner_s:
    #n1:size_t
  -> #n2:size_t{v n1 * v n2 <= max_size_t}
  -> #n3:size_t{v n2 * v n3 <= max_size_t /\ v n1 * v n3 <= max_size_t}
  -> a:matrix_t n1 n2
  -> b:matrix_t n2 n3
  -> i:size_t{v i < v n1}
  -> k:size_t{v k < v n3}
  -> Stack uint16
    (requires fun h -> B.live h a /\ B.live h b)
    (ensures  fun h0 r h1 ->
      modifies loc_none h0 h1 /\
      r == M.mul_inner_s (as_matrix h0 a) (as_matrix h0 b) (v i) (v k))
let mul_inner_s #n1 #n2 #n3 a b i k =
  push_frame();
  let h0 = ST.get() in
  [@ inline_let ]
  let f l = get h0 a (v i) l *. get_s h0 b l (v k) in
  let res = create #uint16 #1 (size 1) (u16 0) in

  let h1 = ST.get() in
  Lib.Loops.for (size 0) n2
    (fun h2 j -> B.live h1 res /\ B.live h2 res /\
      modifies (loc_buffer res) h1 h2 /\
      B.get h2 res 0 == M.sum_ #(v n2) f j)
    (fun j ->
      let aij = mget a i j in
      let bjk = mget_s b j k in
      let res0 = res.(size 0) in
      res.(size 0) <- res0 +. aij *. bjk
    );
  let res = res.(size 0) in
  M.sum_extensionality (v n2) f (fun l -> get h0 a (v i) l *. get_s h0 b l (v k)) (v n2);
  assert (res == M.mul_inner_s (as_matrix h0 a) (as_matrix h0 b) (v i) (v k));
  pop_frame();
  res

#reset-options "--z3rlimit 50 --max_fuel 0 --max_ifuel 0"

inline_for_extraction noextract private
val mul_inner1_s:
    #n1:size_t
  -> #n2:size_t{v n1 * v n2 <= max_size_t}
  -> #n3:size_t{v n2 * v n3 <= max_size_t /\ v n1 * v n3 <= max_size_t}
  -> h0:HS.mem
  -> h1:HS.mem
  -> a:matrix_t n1 n2
  -> b:matrix_t n2 n3
  -> c:matrix_t n1 n3{B.disjoint a c /\ B.disjoint b c}
  -> i:size_t{v i < v n1}
  -> k:size_t{v k < v n3}
  -> f:(k:nat{k < v n3}
       -> GTot (res:uint16{res == M.sum #(v n2) (fun l -> get h0 a (v i) l *. get_s h0 b l k)}))
  -> Stack unit
    (requires fun h2 -> mul_inner_inv h0 h1 h2 a b c f i (v k))
    (ensures  fun _ _ h2 -> mul_inner_inv h0 h1 h2 a b c f i (v k + 1))
let mul_inner1_s #n1 #n2 #n3 h0 h1 a b c i k f =
  assert (M.mul_inner_s (as_matrix h0 a) (as_matrix h0 b) (v i) (v k) ==
          M.sum #(v n2) (fun l -> get h0 a (v i) l *. get_s h0 b l (v k)));
  mset c i k (mul_inner_s a b i k);
  let h2 = ST.get () in
  assert (get h2 c (v i) (v k) == f (v k))

val matrix_mul_s:
    #n1:size_t
  -> #n2:size_t{v n1 * v n2 <= max_size_t}
  -> #n3:size_t{v n2 * v n3 <= max_size_t /\ v n1 * v n3 <= max_size_t}
  -> a:matrix_t n1 n2
  -> b:matrix_t n2 n3
  -> c:matrix_t n1 n3
  -> Stack unit
    (requires fun h ->
      B.live h a /\ B.live h b /\ B.live h c /\ B.disjoint a c /\ B.disjoint b c)
    (ensures  fun h0 _ h1 ->
      B.live h1 c /\
      modifies (loc_buffer c) h0 h1 /\
      as_matrix h1 c == M.mul_s (as_matrix h0 a) (as_matrix h0 b))
[@"c_inline"]
let matrix_mul_s #n1 #n2 #n3 a b c =
  let h0 = ST.get () in
  let f (i:nat{i < v n1}) (k:nat{k < v n3}) :
    GTot (res:uint16{res == M.sum #(v n2) (fun l -> get h0 a i l *. get_s h0 b l k)})
  = M.sum #(v n2) (fun l -> get h0 a i l *. get_s h0 b l k)
  in
  Lib.Loops.for (size 0) n1
    (fun h1 i ->
      B.live h1 a /\ B.live h1 b /\ B.live h1 c /\
      modifies (loc_buffer c) h0 h1 /\ i <= v n1 /\
      (forall (i1:nat{i1 < i}) (k:nat{k < v n3}). get h1 c i1 k == f i1 k) /\
      (forall (i1:nat{i <= i1 /\ i1 < v n1}) (k:nat{k < v n3}). get h1 c i1 k == get h0 c i1 k))
    (fun i ->
      let h1 = ST.get() in
      Lib.Loops.for (size 0) n3
        (fun h2 k -> mul_inner_inv h0 h1 h2 a b c (f (v i)) i k)
        (fun k -> mul_inner1_s h0 h1 a b c i k (f (v i)));
      let h1 = ST.get() in
      let q i1 = forall k. get h1 c i1 k == f i1 k in
      onemore (fun i1 -> i1 < v n1) q (v i)
    );
  let h2 = ST.get() in
  M.extensionality (as_matrix h2 c) (M.mul_s (as_matrix h0 a) (as_matrix h0 b))

(* the end of the special matrix multiplication *)

val eq_u32_m:
    m:size_t{0 < v m /\ v m <= 16}
  -> a:uint16
  -> b:uint16
  -> res:bool{res == M.eq_m (v m) a b}
[@ "substitute"]
let eq_u32_m m a b =
  let open Lib.RawIntTypes in
  let open FStar.UInt32 in
  [@inline_let]
  let m1 = size_to_uint32 m in
  [@inline_let]
  let res = u32_to_UInt32 (to_u32 a &. ((u32 1 <<. m1) -. u32 1)) =^ u32_to_UInt32 (to_u32 b &. (u32 1 <<. m1) -. u32 1) in
  Lemmas.modulo_pow2_u32 (to_u32 a) (uint_v m1);
  Lemmas.modulo_pow2_u32 (to_u32 b) (uint_v m1);
  res

#reset-options "--z3rlimit 50 --max_fuel 1 --max_ifuel 0"

val matrix_eq:
    #n1:size_t
  -> #n2:size_t{v n1 * v n2 <= max_size_t}
  -> m:size_t{0 < v m /\ v m <= 16}
  -> a:matrix_t n1 n2
  -> b:matrix_t n1 n2
  -> Stack bool
    (requires fun h -> B.live h a /\ B.live h b)
    (ensures  fun h0 r h1 -> modifies loc_none h0 h1 /\
      r == M.matrix_eq #(v n1) #(v n2) (v m) (as_matrix h0 a) (as_matrix h0 b))
[@"c_inline"]
let matrix_eq #n1 #n2 m a b =
  push_frame();
  let res = create #bool #1 (size 1) true in

  let n = n1 *! n2 in
  let h0 = ST.get() in
  Lib.Loops.for (size 0) n
  (fun h1 i ->
    B.live h1 res /\ modifies (loc_buffer res) h0 h1 /\
    B.get h1 res 0 == M.matrix_eq_fc #(v n1) #(v n2) (v m) (as_matrix h0 a) (as_matrix h0 b) i)
  (fun i ->
    let ai = a.(i) in
    let bi = b.(i) in
    let a1 = res.(size 0) in
    res.(size 0) <- a1 && eq_u32_m m ai bi
  );
  let res = res.(size 0) in
  pop_frame();
  res

#reset-options "--z3rlimit 150 --max_fuel 0"

val matrix_to_lbytes:
    #n1:size_t
  -> #n2:size_t{2 * v n1 <= max_size_t /\ 2 * v n1 * v n2 <= max_size_t}
  -> m:matrix_t n1 n2
  -> res:lbytes (size 2 *! n1 *! n2)
  -> Stack unit
    (requires fun h -> live h m /\ live h res /\ disjoint m res)
    (ensures  fun h0 r h1 ->
      live h1 res /\ modifies (loc_buffer res) h0 h1 /\
      B.as_seq h1 res == M.matrix_to_lbytes #(v n1) #(v n2) (as_matrix h0 m))
[@"c_inline"]
let matrix_to_lbytes #n1 #n2 m res =
  let h0 = ST.get () in
  let n = n1 *! n2 in
  Lib.Loops.for (size 0) n
  (fun h1 i ->
    B.live h1 m /\ B.live h1 res /\ modifies (loc_buffer res) h0 h1 /\
    (forall (i0:size_nat{i0 < i}) (k:size_nat{k < 2}). M.matrix_to_lbytes_fc (as_matrix h0 m) (B.as_seq h1 res) i0 k))
  (fun i ->
    M.lemma_uint_to_bytes_le (Seq.index #uint16 #(v n1 * v n2) (B.as_seq h0 m) (v i));
    let tmp = sub res (size 2 *! i) (size 2) in
    let h0 = ST.get () in
    uint_to_bytes_le tmp m.(i);
    let h1 = ST.get () in
    modifies_buffer_elim ((sub #_ #(2 * v n1 * v n2) #(2 * v i) res (size 0) (size 2 *! i))) (loc_buffer tmp) h0 h1;
    //assert (Seq.sub #_ #(2 * v n1 * v n2) (as_seq h1 res) 0 (2 * v i) == Seq.sub #_ #(2 * v n1 * v n2) (as_seq h0 res) 0 (2 * v i));
    M.lemma_matrix_to_lbytes #(v n1) #(v n2) (as_matrix h0 m) (B.as_seq h0 res) (B.as_seq h1 res) (v i)
  );
  let h1 = ST.get () in
  M.lemma_matrix_to_lbytes_ext #(v n1) #(v n2) (as_matrix h0 m) (B.as_seq h1 res) (M.matrix_to_lbytes #(v n1) #(v n2) (as_matrix h0 m))

val matrix_from_lbytes:
    #n1:size_t
  -> #n2:size_t{2 * v n1 <= max_size_t /\ 2 * v n1 * v n2 <= max_size_t}
  -> b:lbytes (size 2 *! n1 *! n2)
  -> res:matrix_t n1 n2
  -> Stack unit
    (requires fun h -> live h b /\ live h res /\ disjoint b res)
    (ensures  fun h0 _ h1 ->
      live h1 res /\ modifies (loc_buffer res) h0 h1 /\
      B.as_seq h1 res == M.matrix_from_lbytes (v n1) (v n2) (B.as_seq h0 b))
[@"c_inline"]
let matrix_from_lbytes #n1 #n2 b res =
  let h0 = ST.get () in
  let n = n1 *! n2 in
  Lib.Loops.for (size 0) n
  (fun h1 i ->
    B.live h1 b /\ B.live h1 res /\ modifies (loc_buffer res) h0 h1 /\
    (forall (i0:size_nat{i0 < i}). bget h1 res i0 == M.matrix_from_lbytes_fc (v n1) (v n2) (B.as_seq h0 b) i0))
  (fun i ->
    res.(i) <- uint_from_bytes_le #U16 (sub b (size 2 *! i) (size 2))
  );
  let h1 = ST.get () in
  Seq.eq_intro (B.as_seq h1 res) (M.matrix_from_lbytes (v n1) (v n2) (B.as_seq h0 b))
