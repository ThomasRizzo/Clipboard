(*
    mkr_parser.fs
    =============

    F# parser using FParsec for VNA / Network Analyzer marker data.

    Sample Input Data:
    ------------------
    #Port 1 Frq 1.3GHz
    !MKR 099_01 : +12345.66 -23.45
    !MKR 099_02 : +12355.66 -21.45
    !MKR 099_03 : +12365.66 -20.45
    #Port 1 Frq 1.5GHz
    !MKR 099_01 : +12345.66 -23.45
    !MKR 099_02 : +12355.66 -21.45
    !MKR 099_03 : +12365.66 -20.45

    New supported formats (case insensitive):
    #Port 1 Frq 1300MHz
    #Port 1 Frq 1300000KHz
    #Port 1 Frq 1.3GHz

    Record Definition:
    ------------------
    type MarkerData =
        { port: float
          inputfreq_Hz: float     // Now in Hz (converted from KHz/MHz/GHz)
          channel: float
          marker: float
          freq_Hz: float
          mag_DBm: float }

    Notes:
    ------
    - Parses repeating blocks starting with #Port X Frq Y.Z<unit>
    - Supports KHz, MHz, GHz (case insensitive)
    - Automatically converts input frequency to Hz
    - Each block can have 0 or more !MKR lines
    - Extracts channel and marker from format like "099_01"
    - Returns seq<MarkerData> for easy processing
    - Robust handling of whitespace and newlines
    - Uses FParsec combinators
*) 

open FParsec

type MarkerData =
    { port: float
      inputfreq_Hz: float
      channel: float
      marker: float
      freq_Hz: float
      mag_DBm: float }

let parseMarkerData (input: string) : seq<MarkerData> =
    // Parser for frequency unit (KHz, MHz, GHz, Hz - case insensitive)
    let pFreqUnit : Parser<float, unit> =
        choice [
            pstringCI "GHz" >>% 1e9
            pstringCI "MHz" >>% 1e6
            pstringCI "KHz" >>% 1e3
            pstringCI "Hz"  >>% 1.0
        ]

    let pHeader: Parser<float * float, unit> =
        skipString "#Port" >>.
        spaces1 >>.
        pfloat >>= fun port ->
            spaces1 >>.
            skipString "Frq" >>.
            spaces1 >>.
            pfloat .>>. pFreqUnit .>>
            skipRestOfLine true
            |>> fun (freqValue, multiplier) ->
                let freqHz = freqValue * multiplier
                (port, freqHz)

    let pMarker (port: float) (inputfreq_Hz: float) : Parser<MarkerData, unit> =
        skipString "!MKR" >>.
        spaces1 >>.
        (pint32 .>> pchar '_' .>>. pint32) >>= fun (ch, mk) ->
            let channel = float ch
            let marker = float mk
            spaces >>.
            pchar ':' >>.
            spaces >>.
            pfloat >>= fun freq_Hz ->
                spaces >>.
                pfloat .>>
                skipRestOfLine true
                |>> fun mag_DBm ->
                    { port = port
                      inputfreq_Hz = inputfreq_Hz
                      channel = channel
                      marker = marker
                      freq_Hz = freq_Hz
                      mag_DBm = mag_DBm }

    let pBlock: Parser<MarkerData list, unit> =
        pHeader >>= fun (port, inputfreq_Hz) ->
            many (pMarker port inputfreq_Hz)

    let pAll: Parser<MarkerData list, unit> =
        spaces >>. many pBlock .>> spaces .>> eof |>> List.concat

    match run pAll input with
    | Success (result, _, _) -> Seq.ofList result
    | Failure (msg, _, _) -> failwithf "Parsing failed: %s" msg
