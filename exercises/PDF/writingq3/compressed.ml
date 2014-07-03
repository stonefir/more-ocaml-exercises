(* Build a PDF file and write it *)
open Input
open Bits

let output_of_buffer b =
  {output_char = Buffer.add_char b;
   out_channel_length = fun () -> Buffer.length b}

(* Run Length Encoding *)
let process f s =
  let b = Buffer.create (String.length s) in
    f (input_of_string s) (output_of_buffer b);
    Buffer.contents b

(* Return the run (of length 1 to 128) of like characters as (byte, count).
 * Raises End_of_file if already at end of file. *)
let getsame i =
  let rec getcount ch c =
    if c = 128 then 128 else
      try
        if i.input_char () = ch then getcount ch (c + 1) else (rewind i; c)
      with
        End_of_file -> c
  in
    let ch = i.input_char () in (ch, getcount ch 1)

(* Get the run (of length 1 to 128) of differing characters as a list. Raises
 * End_of_file if already at end of file at start of function. *)
let getdifferent i =
  let rec getdiffinner a c =
    if c = 128 then List.rev a else
      try
        let ch' = i.input_char () in
          if ch' <> List.hd a
            then getdiffinner (ch' :: a) (c + 1)
            else (rewind i; rewind i; List.rev (List.tl a))
      with
        End_of_file -> List.rev a
  in
    getdiffinner [i.input_char ()] 1

let compress i o =
  try
    while true do
      match getsame i with
        (_, 1) ->
          rewind i;
          let cs = getdifferent i in
            o.output_char (char_of_int (List.length cs - 1));
            List.iter o.output_char cs
      | (b, c) ->
          o.output_char (char_of_int (257 - c));
          o.output_char b
    done
  with
    End_of_file -> o.output_char (char_of_int 128)

let objects str filter =
  [(1,
     Pdf.Dictionary
       [("/Type", Pdf.Name "/Page");
        ("/Parent", Pdf.Indirect 3);
        ("/Resources",
           Pdf.Dictionary
             [("/Font",
                 Pdf.Dictionary
                   [("/F0",
                     Pdf.Dictionary
                       [("/Type", Pdf.Name "/Font");
                        ("/Subtype", Pdf.Name "/Type1");
                        ("/BaseFont", Pdf.Name "/Times-Italic")])])]);
         ("/MediaBox",
             Pdf.Array
               [Pdf.Float 0.; Pdf.Float 0.;
                Pdf.Float 595.275590551; Pdf.Float 841.88976378]);
         ("/Rotate", Pdf.Integer 0);
         ("/Contents", Pdf.Array [Pdf.Indirect 4])]);
   (2,
     Pdf.Dictionary
      [("/Type", Pdf.Name "/Catalog");
       ("/Pages", Pdf.Indirect 3)]);
   (3,
     Pdf.Dictionary
      [("/Type", Pdf.Name "/Pages");
       ("/Kids", Pdf.Array [Pdf.Indirect 1]);
       ("/Count", Pdf.Integer 1)]);
   (4,
     Pdf.Stream
       (Pdf.Dictionary
          [("/Length", Pdf.Integer (String.length str)); filter], str))]

let hello_text =
  let i =
    input_of_string "1 0 0 1 50 770 cm BT /F0 36 Tf (Hello, World!) Tj ET"
  in
    let b = Buffer.create 100 in
      let o = output_of_buffer b in
        compress i o;
        Buffer.contents b

(* CCITT Fax Group 3 Encoding *)
let getbitint b =
  if getbit b then 1 else 0
  
let peekbit b =
  if b.bit = 0 then
    begin
      let byte = int_of_char (b.input.input_char ()) in
        rewind b.input;
        byte land 128 > 0
    end
  else
    b.byte land b.bit > 0

(* Output bit streams *)

(* Flush a byte to the underlying output, padding with zeroes. If output byte
 * has not been touched, don't output. *)

let rec putbit o b =
  if o.obit = -1 then
    begin
      flush o;
      putbit o b
    end
  else
    begin
      if b then o.obyte <- o.obyte lor (1 lsl o.obit);
      o.obit <- o.obit - 1
    end

let putbitint o b =
  putbit o (b = 1)

let putval o v l =
  for x = l - 1 downto 0 do
    putbitint o (v land (1 lsl x))
  done

let e = "((5.000000, 4.583333), (4.500000,5.000000))"

let width = 80

let input_data =
"00000000000000000000000000000000000000000000000000000000000000000000000000000000\
 00000000000000000000000000000000000000000000000000000000000000000000000001000000\
 00000000111111110000000000011111111100000000000000000000000000000000000111100000\
 00000011000000011100000001110000001110000000000000000000000000000000000011000000\
 00000110000000001110000011000000000110000000000000000000000000000000000011000000\
 00001110000000000111000111000000000000000000000000000000000000000000000011000000\
 00001100000000000111000110000000000000000000000000000000000000000000000011000000\
 00001100000000000011001110000000000000000011100000000100111000011100000011000000\
 00011100000000000011001110000000000000001111111000111111111101111110000001000000\
 00011100000000000011101100000000000000001000011000001110001111000111000001000000\
 00011100000000000011101100000000000000000000011000001100000110000011000001000000\
 00011100000000000011001110000000000000000000011000001100000110000011000001000000\
 00001100000000000011001110000000000000000111011000001100000110000011000001000000\
 00001110000000000011000110000000000000011100011000001100000110000011000001000000\
 00001110000000000110000111000000000000011000011000001100000110000011000011000000\
 00000111000000000110000011100000000000011000011000001100000110000011000011100000\
 00000011100000001100000001110000000010010001110000011000001100000110000111000000\
 00000011111111100000000001111111111000111110111000111100011110000111001111100000\
 00000000011100000000000000001111000000001000000000000000000000000000000000000000\
 00000000000000000000000000000000000000000000000000000000000000000000000000000000\
 00000000000000000000000000000000000000000000000000000000000000000000000000000000"

let text = "1010101010"


let white_terminating_codes =
  [|[0; 0; 1; 1; 0; 1; 0; 1]; 
    [0; 0; 0; 1; 1; 1];
    [0; 1; 1; 1];
    [1; 0; 0; 0];
    [1; 0; 1; 1];
    [1; 1; 0; 0];
    [1; 1; 1; 0];
    [1; 1; 1; 1];
    [1; 0; 0; 1; 1];
    [1; 0; 1; 0; 0];
    [0; 0; 1; 1; 1];
    [0; 1; 0; 0; 0];
    [0; 0; 1; 0; 0; 0];
    [0; 0; 0; 0; 1; 1];
    [1; 1; 0; 1; 0; 0];
    [1; 1; 0; 1; 0; 1];
    [1; 0; 1; 0; 1; 0];
    [1; 0; 1; 0; 1; 1];
    [0; 1; 0; 0; 1; 1; 1];
    [0; 0; 0; 1; 1; 0; 0];
    [0; 0; 0; 1; 0; 0; 0];
    [0; 0; 1; 0; 1; 1; 1];
    [0; 0; 0; 0; 0; 1; 1];
    [0; 0; 0; 0; 1; 0; 0];
    [0; 1; 0; 1; 0; 0; 0];
    [0; 1; 0; 1; 0; 1; 1];
    [0; 0; 1; 0; 0; 1; 1];
    [0; 1; 0; 0; 1; 0; 0];
    [0; 0; 1; 1; 0; 0; 0];
    [0; 0; 0; 0; 0; 0; 1; 0];
    [0; 0; 0; 0; 0; 0; 1; 1];
    [0; 0; 0; 1; 1; 0; 1; 0];
    [0; 0; 0; 1; 1; 0; 1; 1];
    [0; 0; 0; 1; 0; 0; 1; 0];
    [0; 0; 0; 1; 0; 0; 1; 1];
    [0; 0; 0; 1; 0; 1; 0; 0];
    [0; 0; 0; 1; 0; 1; 0; 1];
    [0; 0; 0; 1; 0; 1; 1; 0];
    [0; 0; 0; 1; 0; 1; 1; 1];
    [0; 0; 1; 0; 1; 0; 0; 0];
    [0; 0; 1; 0; 1; 0; 0; 1];
    [0; 0; 1; 0; 1; 0; 1; 0];
    [0; 0; 1; 0; 1; 0; 1; 1];
    [0; 0; 1; 0; 1; 1; 0; 0];
    [0; 0; 1; 0; 1; 1; 0; 1];
    [0; 0; 0; 0; 0; 1; 0; 0];
    [0; 0; 0; 0; 0; 1; 0; 1];
    [0; 0; 0; 0; 1; 0; 1; 0];
    [0; 0; 0; 0; 1; 0; 1; 1];
    [0; 1; 0; 1; 0; 0; 1; 0];
    [0; 1; 0; 1; 0; 0; 1; 1];
    [0; 1; 0; 1; 0; 1; 0; 0];
    [0; 1; 0; 1; 0; 1; 0; 1];
    [0; 0; 1; 0; 0; 1; 0; 0];
    [0; 0; 1; 0; 0; 1; 0; 1];
    [0; 1; 0; 1; 1; 0; 0; 0];
    [0; 1; 0; 1; 1; 0; 0; 1];
    [0; 1; 0; 1; 1; 0; 1; 0];
    [0; 1; 0; 1; 1; 0; 1; 1];
    [0; 1; 0; 0; 1; 0; 1; 0];
    [0; 1; 0; 0; 1; 0; 1; 1];
    [0; 0; 1; 1; 0; 0; 1; 0];
    [0; 0; 1; 1; 0; 0; 1; 1];
    [0; 0; 1; 1; 0; 1; 0; 0]|]

let black_terminating_codes =
  [|[0; 0; 0; 1; 1; 0; 1; 1; 1];
    [0; 1; 0];
    [1; 1];
    [1; 0];
    [0; 1; 1];
    [0; 0; 1; 1];
    [0; 0; 1; 0];
    [0; 0; 0; 1; 1];
    [0; 0; 0; 1; 0; 1];
    [0; 0; 0; 1; 0; 0];
    [0; 0; 0; 0; 1; 0; 0];
    [0; 0; 0; 0; 1; 0; 1];
    [0; 0; 0; 0; 1; 1; 1];
    [0; 0; 0; 0; 0; 1; 0; 0];
    [0; 0; 0; 0; 0; 1; 1; 1];
    [0; 0; 0; 0; 1; 1; 0; 0; 0];
    [0; 0; 0; 0; 0; 1; 0; 1; 1; 1];
    [0; 0; 0; 0; 0; 1; 1; 0; 0; 0];
    [0; 0; 0; 0; 0; 0; 1; 0; 0; 0];
    [0; 0; 0; 0; 1; 1; 0; 0; 1; 1; 1];
    [0; 0; 0; 0; 1; 1; 0; 1; 0; 0; 0];
    [0; 0; 0; 0; 1; 1; 0; 1; 1; 0; 0];
    [0; 0; 0; 0; 0; 1; 1; 0; 1; 1; 1];
    [0; 0; 0; 0; 0; 1; 0; 1; 0; 0; 0];
    [0; 0; 0; 0; 0; 0; 1; 0; 1; 1; 1];
    [0; 0; 0; 0; 0; 0; 1; 1; 0; 0; 0];
    [0; 0; 0; 0; 1; 1; 0; 0; 1; 0; 1; 0];
    [0; 0; 0; 0; 1; 1; 0; 0; 1; 0; 1; 1];
    [0; 0; 0; 0; 1; 1; 0; 0; 1; 1; 0; 0];
    [0; 0; 0; 0; 1; 1; 0; 0; 1; 1; 0; 1];
    [0; 0; 0; 0; 0; 1; 1; 0; 1; 0; 0; 0];
    [0; 0; 0; 0; 0; 1; 1; 0; 1; 0; 0; 1];
    [0; 0; 0; 0; 0; 1; 1; 0; 1; 0; 1; 0];
    [0; 0; 0; 0; 0; 1; 1; 0; 1; 0; 1; 1];
    [0; 0; 0; 0; 1; 1; 0; 1; 0; 0; 1; 0];
    [0; 0; 0; 0; 1; 1; 0; 1; 0; 0; 1; 1];
    [0; 0; 0; 0; 1; 1; 0; 1; 0; 1; 0; 1];
    [0; 0; 0; 0; 1; 1; 0; 1; 0; 1; 1; 0];
    [0; 0; 0; 0; 1; 1; 0; 1; 0; 1; 1; 1];
    [0; 0; 0; 0; 0; 1; 1; 0; 1; 1; 0; 0];
    [0; 0; 0; 0; 0; 1; 1; 0; 1; 1; 0; 1];
    [0; 0; 0; 0; 1; 1; 0; 1; 1; 0; 1; 0];
    [0; 0; 0; 0; 1; 1; 0; 1; 1; 0; 1; 1];
    [0; 0; 0; 0; 0; 1; 0; 1; 0; 1; 0; 0];
    [0; 0; 0; 0; 0; 1; 0; 1; 0; 1; 0; 1];
    [0; 0; 0; 0; 0; 1; 0; 1; 0; 1; 1; 0];
    [0; 0; 0; 0; 0; 1; 0; 1; 0; 1; 1; 1];
    [0; 0; 0; 0; 0; 1; 1; 0; 0; 1; 0; 0];
    [0; 0; 0; 0; 0; 1; 1; 0; 0; 1; 0; 1];
    [0; 0; 0; 0; 0; 1; 0; 1; 0; 0; 1; 0];
    [0; 0; 0; 0; 0; 1; 0; 1; 0; 0; 1; 1];
    [0; 0; 0; 0; 0; 0; 1; 0; 0; 1; 0; 0];
    [0; 0; 0; 0; 0; 0; 1; 1; 0; 1; 1; 1];
    [0; 0; 0; 0; 0; 0; 1; 1; 1; 0; 0; 0];
    [0; 0; 0; 0; 0; 0; 1; 0; 0; 1; 1; 1];
    [0; 0; 0; 0; 0; 0; 1; 0; 1; 0; 0; 0];
    [0; 0; 0; 0; 0; 1; 0; 1; 1; 0; 0; 0];
    [0; 0; 0; 0; 0; 1; 0; 1; 1; 0; 0; 1];
    [0; 0; 0; 0; 0; 0; 1; 0; 1; 0; 1; 1];
    [0; 0; 0; 0; 0; 0; 1; 0; 1; 1; 0; 0];
    [0; 0; 0; 0; 0; 1; 0; 1; 1; 0; 1; 0];
    [0; 0; 0; 0; 0; 1; 1; 0; 0; 1; 1; 0];
    [0; 0; 0; 0; 0; 1; 1; 0; 0; 1; 1; 1]|]

let white_make_up_codes =
  [|[1; 1; 0; 1; 1];
    [1; 0; 0; 1; 0];
    [0; 1; 0; 1; 1; 1];
    [0; 1; 1; 0; 1; 1; 1];
    [0; 0; 1; 1; 0; 1; 1; 0];
    [0; 0; 1; 1; 0; 1; 1; 1];
    [0; 1; 1; 0; 0; 1; 0; 0];
    [0; 1; 1; 0; 0; 1; 0; 1];
    [0; 1; 1; 0; 1; 0; 0; 0];
    [0; 1; 1; 0; 0; 1; 1; 1];
    [0; 1; 1; 0; 0; 1; 1; 0; 0];
    [0; 1; 1; 0; 0; 1; 1; 0; 1];
    [0; 1; 1; 0; 1; 0; 0; 1; 0];
    [0; 1; 1; 0; 1; 0; 0; 1; 1];
    [0; 1; 1; 0; 1; 0; 1; 0; 0];
    [0; 1; 1; 0; 1; 0; 1; 0; 1];
    [0; 1; 1; 0; 1; 0; 1; 1; 0];
    [0; 1; 1; 0; 1; 0; 1; 1; 1];
    [0; 1; 1; 0; 1; 1; 0; 0; 0];
    [0; 1; 1; 0; 1; 1; 0; 0; 1];
    [0; 1; 1; 0; 1; 1; 0; 1; 0];
    [0; 1; 1; 0; 1; 1; 0; 1; 1];
    [0; 1; 0; 0; 1; 1; 0; 0; 0];
    [0; 1; 0; 0; 1; 1; 0; 0; 1];
    [0; 1; 1; 0; 0; 0];
    [0; 1; 0; 0; 1; 1; 0; 1; 1]|]

let black_make_up_codes =
  [|[0; 0; 0; 0; 0; 0; 1; 1; 1; 1];
    [0; 0; 0; 0; 1; 1; 0; 0; 1; 0; 0; 0];
    [0; 0; 0; 0; 1; 1; 0; 0; 1; 0; 0; 1];
    [0; 0; 0; 0; 0; 1; 0; 1; 1; 0; 1; 1];
    [0; 0; 0; 0; 0; 0; 1; 1; 0; 0; 1; 1];
    [0; 0; 0; 0; 0; 0; 1; 1; 0; 1; 0; 0];
    [0; 0; 0; 0; 0; 0; 1; 1; 0; 1; 0; 1];
    [0; 0; 0; 0; 0; 0; 1; 1; 0; 1; 1; 0; 0];
    [0; 0; 0; 0; 0; 0; 1; 1; 0; 1; 1; 0; 1];
    [0; 0; 0; 0; 0; 0; 1; 0; 0; 1; 0; 1; 0];
    [0; 0; 0; 0; 0; 0; 1; 0; 0; 1; 0; 1; 1];
    [0; 0; 0; 0; 0; 0; 1; 0; 0; 1; 1; 0; 0];
    [0; 0; 0; 0; 0; 0; 1; 0; 0; 1; 1; 0; 1];
    [0; 0; 0; 0; 0; 0; 1; 1; 1; 0; 0; 1; 0];
    [0; 0; 0; 0; 0; 0; 1; 1; 1; 0; 0; 1; 1];
    [0; 0; 0; 0; 0; 0; 1; 1; 1; 0; 1; 0; 0];
    [0; 0; 0; 0; 0; 0; 1; 1; 1; 0; 1; 0; 1];
    [0; 0; 0; 0; 0; 0; 1; 1; 1; 0; 1; 1; 0];
    [0; 0; 0; 0; 0; 0; 1; 1; 1; 0; 1; 1; 1];
    [0; 0; 0; 0; 0; 0; 1; 0; 1; 0; 0; 1; 0];
    [0; 0; 0; 0; 0; 0; 1; 0; 1; 0; 0; 1; 1];
    [0; 0; 0; 0; 0; 0; 1; 0; 1; 0; 1; 0; 0];
    [0; 0; 0; 0; 0; 0; 1; 0; 1; 0; 1; 0; 1];
    [0; 0; 0; 0; 0; 0; 1; 0; 1; 1; 0; 1; 0];
    [0; 0; 0; 0; 0; 0; 1; 0; 1; 1; 0; 1; 1];
    [0; 0; 0; 0; 0; 0; 1; 1; 0; 0; 1; 0; 0];
    [0; 0; 0; 0; 0; 0; 1; 1; 0; 0; 1; 0; 1]|]

(* find the code *)
let rec code isblack length =
  if length > 1776 || length < 0 then
    raise (Invalid_argument "codes: bad length")
  else
    if length > 64 then
      let m =
        if isblack
          then black_make_up_codes.(length / 64 - 1)
          else white_make_up_codes.(length / 64 - 1)
      in
        m @ code isblack (length mod 64)
    else
      if isblack
        then black_terminating_codes.(length)
        else white_terminating_codes.(length)

(* Convert the example string to a string containing just the bits, padded with
 * zeroes to a full byte. *)
let packedstring_of_string s =
  let b = Buffer.create (String.length s / 8 + 1) in
  let o = output_bits_of_output (output_of_buffer b) in
    for x = 0 to String.length s - 1 do putbit o (s.[x] = '1') done;
    flush o;
    Buffer.contents b

let print_packedstring w s =
  let ibits = input_bits_of_input (input_of_string s) in
    try
      while true do
        for column = 1 to w do print_int (getbitint ibits) done;
        print_newline ()
      done
    with
      End_of_file -> ()

(* Given input and output bitstreams and width and height, encode using CCITT
 * group 3 fax. There must be (w * h) bits in the input. *)
let rec read_up_to v i n w =
  if n >= w then (n, v) else
    match peekbit i with
      x when x = v -> (ignore (getbit i)); read_up_to v i (n + 1) w
    | x -> (n, v)

let encode_fax i o w h =
  let rec encode_fax_line i o w =
    if w > 0 then
      let n, isblack = read_up_to (peekbit i) i 0 w in
        List.iter (putbitint o) (code isblack n);
        encode_fax_line i o (w - n)
  in
    for x = 1 to h do
      if peekbit i then List.iter (putbitint o) (code true 0);
      encode_fax_line i o w
    done

let rec read_white_code i =
  let a = getbitint i in
  let b = getbitint i in
  let c = getbitint i in
  let d = getbitint i in
    match a, b, c, d with
    | 0, 1, 1, 1 -> 2
    | 1, 0, 0, 0 -> 3
    | 1, 0, 1, 1 -> 4
    | 1, 1, 0, 0 -> 5
    | 1, 1, 1, 0 -> 6
    | 1, 1, 1, 1 -> 7
    | _ ->
  let e = getbitint i in
    match a, b, c, d, e with
    | 1, 0, 0, 1, 1 -> 8
    | 1, 0, 1, 0, 0 -> 9
    | 0, 0, 1, 1, 1 -> 10
    | 0, 1, 0, 0, 0 -> 11
    | 1, 1, 0, 1, 1 -> 64 + read_white_code i
    | 1, 0, 0, 1, 0 -> 128 + read_white_code i
    | _ ->
  let f = getbitint i in
    match a, b, c, d, e, f with
    | 0, 0, 0, 1, 1, 1 -> 1
    | 0, 0, 1, 0, 0, 0 -> 12
    | 0, 0, 0, 0, 1, 1 -> 13
    | 1, 1, 0, 1, 0, 0 -> 14
    | 1, 1, 0, 1, 0, 1 -> 15
    | 1, 0, 1, 0, 1, 0 -> 16
    | 1, 0, 1, 0, 1, 1 -> 17
    | 0, 1, 0, 1, 1, 1 -> 192 + read_white_code i
    | 0, 1, 1, 0, 0, 0 -> 1664 + read_white_code i
    | _ ->
  let g = getbitint i in
    match a, b, c, d, e, f, g with
    | 0, 1, 0, 0, 1, 1, 1 -> 18
    | 0, 0, 0, 1, 1, 0, 0 -> 19
    | 0, 0, 0, 1, 0, 0, 0 -> 20
    | 0, 0, 1, 0, 1, 1, 1 -> 21
    | 0, 0, 0, 0, 0, 1, 1 -> 22
    | 0, 0, 0, 0, 1, 0, 0 -> 23
    | 0, 1, 0, 1, 0, 0, 0 -> 24
    | 0, 1, 0, 1, 0, 1, 1 -> 25
    | 0, 0, 1, 0, 0, 1, 1 -> 26
    | 0, 1, 0, 0, 1, 0, 0 -> 27
    | 0, 0, 1, 1, 0, 0, 0 -> 28
    | 0, 1, 1, 0, 1, 1, 1 -> 256 + read_white_code i
    | _ ->
  let h = getbitint i in
    match a, b, c, d, e, f, g, h with
    | 0, 0, 1, 1, 0, 1, 0, 1 -> 0
    | 0, 0, 0, 0, 0, 0, 1, 0 -> 29
    | 0, 0, 0, 0, 0, 0, 1, 1 -> 30
    | 0, 0, 0, 1, 1, 0, 1, 0 -> 31
    | 0, 0, 0, 1, 1, 0, 1, 1 -> 32
    | 0, 0, 0, 1, 0, 0, 1, 0 -> 33
    | 0, 0, 0, 1, 0, 0, 1, 1 -> 34
    | 0, 0, 0, 1, 0, 1, 0, 0 -> 35
    | 0, 0, 0, 1, 0, 1, 0, 1 -> 36
    | 0, 0, 0, 1, 0, 1, 1, 0 -> 37
    | 0, 0, 0, 1, 0, 1, 1, 1 -> 38
    | 0, 0, 1, 0, 1, 0, 0, 0 -> 39
    | 0, 0, 1, 0, 1, 0, 0, 1 -> 40
    | 0, 0, 1, 0, 1, 0, 1, 0 -> 41
    | 0, 0, 1, 0, 1, 0, 1, 1 -> 42
    | 0, 0, 1, 0, 1, 1, 0, 0 -> 43
    | 0, 0, 1, 0, 1, 1, 0, 1 -> 44
    | 0, 0, 0, 0, 0, 1, 0, 0 -> 45
    | 0, 0, 0, 0, 0, 1, 0, 1 -> 46
    | 0, 0, 0, 0, 1, 0, 1, 0 -> 47
    | 0, 0, 0, 0, 1, 0, 1, 1 -> 48
    | 0, 1, 0, 1, 0, 0, 1, 0 -> 49
    | 0, 1, 0, 1, 0, 0, 1, 1 -> 50
    | 0, 1, 0, 1, 0, 1, 0, 0 -> 51
    | 0, 1, 0, 1, 0, 1, 0, 1 -> 52
    | 0, 0, 1, 0, 0, 1, 0, 0 -> 53
    | 0, 0, 1, 0, 0, 1, 0, 1 -> 54
    | 0, 1, 0, 1, 1, 0, 0, 0 -> 55
    | 0, 1, 0, 1, 1, 0, 0, 1 -> 56
    | 0, 1, 0, 1, 1, 0, 1, 0 -> 57
    | 0, 1, 0, 1, 1, 0, 1, 1 -> 58
    | 0, 1, 0, 0, 1, 0, 1, 0 -> 59
    | 0, 1, 0, 0, 1, 0, 1, 1 -> 60
    | 0, 0, 1, 1, 0, 0, 1, 0 -> 61
    | 0, 0, 1, 1, 0, 0, 1, 1 -> 62
    | 0, 0, 1, 1, 0, 1, 0, 0 -> 63
    | 0, 0, 1, 1, 0, 1, 1, 0 -> 320 + read_white_code i
    | 0, 0, 1, 1, 0, 1, 1, 1 -> 384 + read_white_code i
    | 0, 1, 1, 0, 0, 1, 0, 0 -> 448 + read_white_code i
    | 0, 1, 1, 0, 0, 1, 0, 1 -> 512 + read_white_code i
    | 0, 1, 1, 0, 1, 0, 0, 0 -> 576 + read_white_code i
    | 0, 1, 1, 0, 0, 1, 1, 1 -> 640 + read_white_code i
    | _ ->
  let j = getbitint i in
    match a, b, c, d, e, f, g, h, j with
    | 0, 1, 1, 0, 0, 1, 1, 0, 0 -> 704 + read_white_code i
    | 0, 1, 1, 0, 0, 1, 1, 0, 1 -> 768 + read_white_code i
    | 0, 1, 1, 0, 1, 0, 0, 1, 0 -> 832 + read_white_code i
    | 0, 1, 1, 0, 1, 0, 0, 1, 1 -> 896 + read_white_code i
    | 0, 1, 1, 0, 1, 0, 1, 0, 0 -> 960 + read_white_code i
    | 0, 1, 1, 0, 1, 0, 1, 0, 1 -> 1024 + read_white_code i
    | 0, 1, 1, 0, 1, 0, 1, 1, 0 -> 1088 + read_white_code i
    | 0, 1, 1, 0, 1, 0, 1, 1, 1 -> 1152 + read_white_code i
    | 0, 1, 1, 0, 1, 1, 0, 0, 0 -> 1216 + read_white_code i
    | 0, 1, 1, 0, 1, 1, 0, 0, 1 -> 1280 + read_white_code i
    | 0, 1, 1, 0, 1, 1, 0, 1, 0 -> 1344 + read_white_code i
    | 0, 1, 1, 0, 1, 1, 0, 1, 1 -> 1408 + read_white_code i
    | 0, 1, 0, 0, 1, 1, 0, 0, 0 -> 1472 + read_white_code i
    | 0, 1, 0, 0, 1, 1, 0, 0, 1 -> 1536 + read_white_code i
    | 0, 1, 0, 0, 1, 1, 0, 1, 0 -> 1600 + read_white_code i
    | 0, 1, 0, 0, 1, 1, 0, 1, 1 -> 1728 + read_white_code i
    | _ -> raise (Failure "bad white code")

let rec read_black_code i =
  let a = getbitint i in
  let b = getbitint i in
    match a, b with
    | 1, 1 -> 2
    | 1, 0 -> 3
    | _ ->
  let c = getbitint i in
    match a, b, c with
    | 0, 1, 0 -> 1
    | 0, 1, 1 -> 4
    | _ ->
  let d = getbitint i in
    match a, b, c, d with
    | 0, 0, 1, 1 -> 5
    | 0, 0, 1, 0 -> 6
    | _ ->
  let e = getbitint i in
    match a, b, c, d, e with
    | 0, 0, 0, 1, 1 -> 7
    | _ ->
  let f = getbitint i in
    match a, b, c, d, e, f with
    | 0, 0, 0, 1, 0, 1 -> 8
    | 0, 0, 0, 1, 0, 0 -> 9
    | _ ->
  let g = getbitint i in
    match a, b, c, d, e, f, g with
    | 0, 0, 0, 0, 1, 0, 0 -> 10
    | 0, 0, 0, 0, 1, 0, 1 -> 11
    | 0, 0, 0, 0, 1, 1, 1 -> 12
    | _ ->
  let h = getbitint i in
    match a, b, c, d, e, f, g, h with
    | 0, 0, 0, 0, 0, 1, 0, 0 -> 13
    | 0, 0, 0, 0, 0, 1, 1, 1 -> 14
    | _ ->
  let j = getbitint i in
    match a, b, c, d, e, f, g, h, j with
    | 0, 0, 0, 0, 1, 1, 0, 0, 0 -> 15
    | _ ->
  let k = getbitint i in
    match a, b, c, d, e, f, g, h, j, k with
    | 0, 0, 0, 0, 1, 1, 0, 1, 1, 1 -> 0
    | 0, 0, 0, 0, 0, 1, 0, 1, 1, 1 -> 16
    | 0, 0, 0, 0, 0, 1, 1, 0, 0, 0 -> 17
    | 0, 0, 0, 0, 0, 0, 1, 0, 0, 0 -> 18
    | 0, 0, 0, 0, 0, 0, 1, 1, 1, 1 -> 64 + read_black_code i
    | _ ->
  let l = getbitint i in
    match a, b, c, d, e, f, g, h, j, k, l with
    | 0, 0, 0, 0, 1, 1, 0, 0, 1, 1, 1 -> 19
    | 0, 0, 0, 0, 1, 1, 0, 1, 0, 0, 0 -> 20
    | 0, 0, 0, 0, 1, 1, 0, 1, 1, 0, 0 -> 21
    | 0, 0, 0, 0, 0, 1, 1, 0, 1, 1, 1 -> 22
    | 0, 0, 0, 0, 0, 1, 0, 1, 0, 0, 0 -> 23
    | 0, 0, 0, 0, 0, 0, 1, 0, 1, 1, 1 -> 24
    | 0, 0, 0, 0, 0, 0, 1, 1, 0, 0, 0 -> 25
    | _ ->
  let m = getbitint i in
    match a, b, c, d, e, f, g, h, j, k, l, m with
    | 0, 0, 0, 0, 1, 1, 0, 0, 1, 0, 1, 0 -> 26
    | 0, 0, 0, 0, 1, 1, 0, 0, 1, 0, 1, 1 -> 27
    | 0, 0, 0, 0, 1, 1, 0, 0, 1, 1, 0, 0 -> 28
    | 0, 0, 0, 0, 1, 1, 0, 0, 1, 1, 0, 1 -> 29
    | 0, 0, 0, 0, 0, 1, 1, 0, 1, 0, 0, 0 -> 30
    | 0, 0, 0, 0, 0, 1, 1, 0, 1, 0, 0, 1 -> 31
    | 0, 0, 0, 0, 0, 1, 1, 0, 1, 0, 1, 0 -> 32
    | 0, 0, 0, 0, 0, 1, 1, 0, 1, 0, 1, 1 -> 33
    | 0, 0, 0, 0, 1, 1, 0, 1, 0, 0, 1, 0 -> 34
    | 0, 0, 0, 0, 1, 1, 0, 1, 0, 0, 1, 1 -> 35
    | 0, 0, 0, 0, 1, 1, 0, 1, 0, 1, 0, 0 -> 36
    | 0, 0, 0, 0, 1, 1, 0, 1, 0, 1, 0, 1 -> 37
    | 0, 0, 0, 0, 1, 1, 0, 1, 0, 1, 1, 0 -> 38
    | 0, 0, 0, 0, 1, 1, 0, 1, 0, 1, 1, 1 -> 39
    | 0, 0, 0, 0, 0, 1, 1, 0, 1, 1, 0, 0 -> 40
    | 0, 0, 0, 0, 0, 1, 1, 0, 1, 1, 0, 1 -> 41
    | 0, 0, 0, 0, 1, 1, 0, 1, 1, 0, 1, 0 -> 42
    | 0, 0, 0, 0, 1, 1, 0, 1, 1, 0, 1, 1 -> 43
    | 0, 0, 0, 0, 0, 1, 0, 1, 0, 1, 0, 0 -> 44
    | 0, 0, 0, 0, 0, 1, 0, 1, 0, 1, 0, 1 -> 45
    | 0, 0, 0, 0, 0, 1, 0, 1, 0, 1, 1, 0 -> 46
    | 0, 0, 0, 0, 0, 1, 0, 1, 0, 1, 1, 1 -> 47
    | 0, 0, 0, 0, 0, 1, 1, 0, 0, 1, 0, 0 -> 48
    | 0, 0, 0, 0, 0, 1, 1, 0, 0, 1, 0, 1 -> 49
    | 0, 0, 0, 0, 0, 1, 0, 1, 0, 0, 1, 0 -> 50
    | 0, 0, 0, 0, 0, 1, 0, 1, 0, 0, 1, 1 -> 51
    | 0, 0, 0, 0, 0, 0, 1, 0, 0, 1, 0, 0 -> 52
    | 0, 0, 0, 0, 0, 0, 1, 1, 0, 1, 1, 1 -> 53
    | 0, 0, 0, 0, 0, 0, 1, 1, 1, 0, 0, 0 -> 54
    | 0, 0, 0, 0, 0, 0, 1, 0, 0, 1, 1, 1 -> 55
    | 0, 0, 0, 0, 0, 0, 1, 0, 1, 0, 0, 0 -> 56
    | 0, 0, 0, 0, 0, 1, 0, 1, 1, 0, 0, 0 -> 57
    | 0, 0, 0, 0, 0, 1, 0, 1, 1, 0, 0, 1 -> 58
    | 0, 0, 0, 0, 0, 0, 1, 0, 1, 0, 1, 1 -> 59
    | 0, 0, 0, 0, 0, 0, 1, 0, 1, 1, 0, 0 -> 60
    | 0, 0, 0, 0, 0, 1, 0, 1, 1, 0, 1, 0 -> 61
    | 0, 0, 0, 0, 0, 1, 1, 0, 0, 1, 1, 0 -> 62
    | 0, 0, 0, 0, 0, 1, 1, 0, 0, 1, 1, 1 -> 63
    | 0, 0, 0, 0, 1, 1, 0, 0, 1, 0, 0, 0 -> 128 + read_black_code i
    | 0, 0, 0, 0, 1, 1, 0, 0, 1, 0, 0, 1 -> 192 + read_black_code i
    | 0, 0, 0, 0, 0, 1, 0, 1, 1, 0, 1, 1 -> 256 + read_black_code i
    | 0, 0, 0, 0, 0, 0, 1, 1, 0, 0, 1, 1 -> 320 + read_black_code i
    | 0, 0, 0, 0, 0, 0, 1, 1, 0, 1, 0, 0 -> 384 + read_black_code i
    | 0, 0, 0, 0, 0, 0, 1, 1, 0, 1, 0, 1 -> 448 + read_black_code i
    | _ ->
  let n = getbitint i in
    match a, b, c, d, e, f, g, h, j, k, l, m, n with
    | 0, 0, 0, 0, 0, 0, 1, 1, 0, 1, 1, 0, 0 -> 512 + read_black_code i
    | 0, 0, 0, 0, 0, 0, 1, 1, 0, 1, 1, 0, 1 -> 576 + read_black_code i
    | 0, 0, 0, 0, 0, 0, 1, 0, 0, 1, 0, 1, 0 -> 640 + read_black_code i
    | 0, 0, 0, 0, 0, 0, 1, 0, 0, 1, 0, 1, 1 -> 704 + read_black_code i
    | 0, 0, 0, 0, 0, 0, 1, 0, 0, 1, 1, 0, 0 -> 768 + read_black_code i
    | 0, 0, 0, 0, 0, 0, 1, 0, 0, 1, 1, 0, 1 -> 832 + read_black_code i
    | 0, 0, 0, 0, 0, 0, 1, 1, 1, 0, 0, 1, 0 -> 896 + read_black_code i
    | 0, 0, 0, 0, 0, 0, 1, 1, 1, 0, 0, 1, 1 -> 960 + read_black_code i
    | 0, 0, 0, 0, 0, 0, 1, 1, 1, 0, 1, 0, 0 -> 1024 + read_black_code i
    | 0, 0, 0, 0, 0, 0, 1, 1, 1, 0, 1, 0, 1 -> 1088 + read_black_code i
    | 0, 0, 0, 0, 0, 0, 1, 1, 1, 0, 1, 1, 0 -> 1152 + read_black_code i
    | 0, 0, 0, 0, 0, 0, 1, 1, 1, 0, 1, 1, 1 -> 1216 + read_black_code i
    | 0, 0, 0, 0, 0, 0, 1, 0, 1, 0, 0, 1, 0 -> 1280 + read_black_code i
    | 0, 0, 0, 0, 0, 0, 1, 0, 1, 0, 0, 1, 1 -> 1344 + read_black_code i
    | 0, 0, 0, 0, 0, 0, 1, 0, 1, 0, 1, 0, 0 -> 1408 + read_black_code i
    | 0, 0, 0, 0, 0, 0, 1, 0, 1, 0, 1, 0, 1 -> 1472 + read_black_code i
    | 0, 0, 0, 0, 0, 0, 1, 0, 1, 1, 0, 1, 0 -> 1536 + read_black_code i
    | 0, 0, 0, 0, 0, 0, 1, 0, 1, 1, 0, 1, 1 -> 1600 + read_black_code i
    | 0, 0, 0, 0, 0, 0, 1, 1, 0, 0, 1, 0, 0 -> 1664 + read_black_code i
    | 0, 0, 0, 0, 0, 0, 1, 1, 0, 0, 1, 0, 1 -> 1728 + read_black_code i
    | _ -> raise (Failure "bad black code")

let decode_fax i o w h =
  let lines = ref h in
  let pixels = ref w in
  let iswhite = ref true in
    while !lines > 0 do
      while !pixels > 0 do
        let n =
          (if !iswhite then read_white_code else read_black_code) i
        in
          for x = 1 to n do
            putbitint o (if !iswhite then 0 else 1)
          done;
          pixels := !pixels - n;
          iswhite := not !iswhite
      done;
      iswhite := true;
      pixels := w;
      lines := !lines - 1
    done

let process f s w h = 
  let b = Buffer.create (String.length s) in
  let ibits = input_bits_of_input (input_of_string s) in
  let obits = output_bits_of_output (output_of_buffer b) in
    f ibits obits w h;
    flush obits;
    Buffer.contents b

let decompress_string = process decode_fax

let compress_string = process encode_fax

let hello_text_ccitt =
  compress_string "1 0 0 1 50 770 cm BT /F0 36 Tf (Hello, World!) Tj ET" (52 * 8) 1

let hello =
  {Pdf.version = (1, 1);
   Pdf.objects = objects hello_text ("/Filter", Pdf.Name "/RunLengthDecode");
   Pdf.trailer =
     Pdf.Dictionary
       [("/Size", Pdf.Integer 5);
        ("/Root", Pdf.Indirect 2);
        ("/ID", Pdf.Array [Pdf.String "FIXME"; Pdf.String "FIXME"])]}

let hello_ccitt =
  {Pdf.version = (1, 1);
   Pdf.objects = objects hello_text_ccitt ("/Filter", Pdf.Name "/CCITTFaxDecode");
   Pdf.trailer =
     Pdf.Dictionary
       [("/Size", Pdf.Integer 5);
        ("/Root", Pdf.Indirect 2);
        ("/ID", Pdf.Array [Pdf.String "FIXME"; Pdf.String "FIXME"])]}

let _ =
  Pdfwrite.pdf_to_file hello "compressed.pdf";
  Pdfwrite.pdf_to_file hello_ccitt "compressed-ccitt.pdf"


