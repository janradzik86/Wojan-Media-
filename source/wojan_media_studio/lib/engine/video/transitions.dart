/// Custom xfade expressions for transitions not built into FFmpeg.
/// In xfade custom expressions P goes from 1 (start) to 0 (end); A/B are the
/// current pixel values of the two inputs; a0..a3/b0..b3 sample planes.

String _samp(String which, String x, String y) =>
    'if(eq(PLANE,0),${which}0($x,$y),if(eq(PLANE,1),${which}1($x,$y),if(eq(PLANE,2),${which}2($x,$y),${which}3($x,$y))))';

/// Black value per plane (YUV: 16 luma / 128 chroma).
const _black = 'if(eq(PLANE,0),16,if(eq(PLANE,3),255,128))';

/// Spin: A rotates & shrinks away, then B spins in growing.
String spinExpr() {
  const q = '(1-P)';
  // shrink factor s and angle
  final sA = '(1-2*$q)';
  final sB = '(2*$q-1)';
  const ang = '($q*2*PI)';
  String rot(String s, String which) {
    final dx = '((X-W/2)/$s)', dy = '((Y-H/2)/$s)';
    final sx = '(W/2+$dx*cos($ang)+$dy*sin($ang))';
    final sy = '(H/2-$dx*sin($ang)+$dy*cos($ang))';
    return 'if(between($sx,0,W-1)*between($sy,0,H-1),${_samp(which, sx, sy)},$_black)';
  }

  return 'if(lt($q,0.5),if(lt($sA,0.01),$_black,${rot(sA, 'a')}),if(lt($sB,0.01),$_black,${rot(sB, 'b')}))';
}

/// Glitch: random horizontal slices switch from A to B with offsets.
String glitchExpr() {
  const r = 'mod(floor(Y/(H/18))*37+floor((1-P)*14)*91,100)/100';
  const off = '((mod(floor(Y/(H/18))*53,7)-3)*W*0.02*sin(PI*P))';
  return 'if(gt($r,P),${_samp('b', 'clip(X+$off,0,W-1)', 'Y')},${_samp('a', 'clip(X-$off,0,W-1)', 'Y')})';
}

/// Spatial "cube" rotation approximation: A squeezes left, B expands from right.
String cubeExpr() {
  const bx = '(W*P)';
  const persA = '(1+0.25*(1-P)*(X/max($bx,1)))';
  const persB = '(1+0.25*P*(1-(X-$bx)/max(W-$bx,1)))';
  final ay = '(H/2+(Y-H/2)*$persA)';
  final by = '(H/2+(Y-H/2)*$persB)';
  return 'if(lt(X,$bx),if(between($ay,0,H-1),${_samp('a', '(X*W/max($bx,1))', ay)},$_black),if(between($by,0,H-1),${_samp('b', '((X-$bx)*W/max(W-$bx,1))', by)},$_black))';
}

/// Film burn: dissolve with bright warm flash in the middle.
String filmBurnExpr() => 'if(eq(PLANE,0),min(255,A*P+B*(1-P)+190*sin(PI*P)),if(eq(PLANE,2),min(255,A*P+B*(1-P)+30*sin(PI*P)),A*P+B*(1-P)))';

/// Returns xfade options for a transition id.
String xfadeOptions(String type) {
  switch (type) {
    case 'spin':
      return "transition=custom:expr='${spinExpr()}'";
    case 'glitch':
      return "transition=custom:expr='${glitchExpr()}'";
    case 'cube':
      return "transition=custom:expr='${cubeExpr()}'";
    case 'filmburn':
      return "transition=custom:expr='${filmBurnExpr()}'";
    default:
      return 'transition=$type';
  }
}
