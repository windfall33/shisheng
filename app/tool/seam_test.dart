import 'dart:io';
import 'dart:typed_data';

void main(List<String> a) {
  final b = File(a[0]).readAsBytesSync();      // 裸 s16le pcm
  final v = ByteData.view(b.buffer, b.offsetInBytes, b.lengthInBytes);
  final n = b.length ~/ 2;
  int s(int i) => v.getInt16(i * 2, Endian.little);
  final cut = n ~/ 3;
  final pauseSamples = 24000 * 140 ~/ 1000;
  final seam1 = cut;                            // A 尾 -> 静音
  final seam2 = cut + pauseSamples;             // 静音 -> B 头
  double rms(int c, int w) {
    var sum = 0.0; var cnt = 0;
    for (var i = c - w; i < c + w; i++) {
      if (i < 0 || i >= n) continue;
      final x = s(i) / 32768.0; sum += x * x; cnt++;
    }
    return (sum / cnt).abs() <= 0 ? 0 : (sum / cnt);
  }
  double d(int i) => ((s(i) - s(i - 1)).abs() / 32768.0);
  print('seam1 delta=${d(seam1).toStringAsFixed(5)} '
      'rmsPrev=${rms(seam1, 240).toStringAsFixed(4)} rmsNext=${rms(seam1 + 2, 240).toStringAsFixed(4)}');
  print('seam2 delta=${d(seam2).toStringAsFixed(5)} '
      'rmsPrev=${rms(seam2, 240).toStringAsFixed(4)} rmsNext=${rms(seam2 + 2, 240).toStringAsFixed(4)}');
  // 最大 delta 出现位置
  var mx = 0.0; var at = 0;
  for (var i = 1; i < n; i++) { final x = d(i); if (x > mx) { mx = x; at = i; } }
  print('max delta=${mx.toStringAsFixed(5)} at ${(at / 24000).toStringAsFixed(2)}s '
      '(seam1 ${(seam1 / 24000).toStringAsFixed(2)}s, seam2 ${(seam2 / 24000).toStringAsFixed(2)}s)');
}
