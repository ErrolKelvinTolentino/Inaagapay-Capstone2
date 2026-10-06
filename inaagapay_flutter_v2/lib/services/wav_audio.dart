import 'dart:convert';
import 'dart:typed_data';

/// Joins PCM WAV responses by their RIFF chunks, including extended headers.
/// Rewrites lengths so players read the entire reply, not just its first part.
class WavAudio {
  const WavAudio._();

  static Uint8List concatenate(List<List<int>> parts) {
    List<int>? format;
    final pcm = BytesBuilder(copy: false);
    for (final part in parts) {
      final bytes = Uint8List.fromList(part);
      if (bytes.length < 12 ||
          ascii.decode(bytes.sublist(0, 4)) != 'RIFF' ||
          ascii.decode(bytes.sublist(8, 12)) != 'WAVE') {
        throw const FormatException('Invalid WAV response');
      }
      final view = ByteData.sublistView(bytes);
      List<int>? partFormat;
      List<int>? data;
      for (var offset = 12; offset + 8 <= bytes.length;) {
        final tag = ascii.decode(bytes.sublist(offset, offset + 4));
        final size = view.getUint32(offset + 4, Endian.little);
        final end = offset + 8 + size;
        if (end > bytes.length) throw const FormatException('Truncated WAV');
        if (tag == 'fmt ') partFormat = bytes.sublist(offset + 8, end);
        if (tag == 'data') data = bytes.sublist(offset + 8, end);
        offset = end + (size.isOdd ? 1 : 0);
      }
      if (partFormat == null || data == null || data.isEmpty) {
        throw const FormatException('Missing WAV audio');
      }
      if (format != null && base64Encode(format) != base64Encode(partFormat)) {
        throw const FormatException('Incompatible WAV chunks');
      }
      format = partFormat;
      pcm.add(data);
    }
    if (format == null) throw const FormatException('No WAV audio');
    final audio = pcm.takeBytes();
    final fmtPad = format.length.isOdd ? 1 : 0;
    final dataPad = audio.length.isOdd ? 1 : 0;
    final output =
        Uint8List(12 + 8 + format.length + fmtPad + 8 + audio.length + dataPad);
    final view = ByteData.sublistView(output);
    output.setRange(0, 4, ascii.encode('RIFF'));
    view.setUint32(4, output.length - 8, Endian.little);
    output.setRange(8, 16, ascii.encode('WAVEfmt '));
    view.setUint32(16, format.length, Endian.little);
    output.setRange(20, 20 + format.length, format);
    final dataOffset = 20 + format.length + fmtPad;
    output.setRange(dataOffset, dataOffset + 4, ascii.encode('data'));
    view.setUint32(dataOffset + 4, audio.length, Endian.little);
    output.setRange(dataOffset + 8, dataOffset + 8 + audio.length, audio);
    return output;
  }
}
