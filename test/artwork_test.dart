import 'package:flutter_test/flutter_test.dart';
import 'package:hivefy/utils/artwork.dart';

void main() {
  test('requests larger YouTube Music artwork while preserving its options', () {
    expect(
      fullPlayerArtworkUrl('https://yt3.googleusercontent.com/image=w120-h120-l90-rj'),
      'https://yt3.googleusercontent.com/image=w1200-h1200-l90-rj',
    );
  });

  test('leaves other artwork and URLs without size parameters unchanged', () {
    const external = 'https://example.com/image=w120-h120';
    const unsized = 'https://yt3.googleusercontent.com/image';
    expect(fullPlayerArtworkUrl(external), external);
    expect(fullPlayerArtworkUrl(unsized), unsized);
    expect(fullPlayerArtworkUrl(''), '');
  });
}
