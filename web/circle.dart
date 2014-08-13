import 'dart:html';
import 'dart:math';
import 'dart:web_gl' as webgl;
import 'package:vector_math/vector_math.dart';
import 'package:vector_math/vector_math_lists.dart';
import 'dart:typed_data';
import 'shader.dart';


class CircleScene {
  int _width, _height;
  webgl.RenderingContext _gl;
  Shader _lineShader, _fillShader;
  webgl.Buffer _vboLines, _vboFills, _ibo;
  int _nLines, _nFills;
  
  CircleScene(CanvasElement canvas) {
    _width  = canvas.width;
    _height = canvas.height;
    _gl     = canvas.getContext("experimental-webgl", {'antialias': false});
    
    _vboLines = _gl.createBuffer();
    _vboFills = _gl.createBuffer();
    _ibo    = _gl.createBuffer();
    
    _initShaders();
    _gl.clearColor(1, 1, 1, 1);
    _gl.viewport(0, 0, _width, _height);
    
    var mProjection = makeOrthographicMatrix(-1.01, 1.01, -1.01, 1.01, -1, 1);

    _lineShader.use();
    _gl.uniformMatrix4fv(_lineShader['uProjection'], false, mProjection.storage);

    _fillShader.use();
    _gl.uniformMatrix4fv(_fillShader['uProjection'], false, mProjection.storage);

    _gl.bindBuffer(webgl.ARRAY_BUFFER, _vboLines);
    _gl.vertexAttribPointer(0, 2, webgl.FLOAT, false, 0, 0);
    _gl.enableVertexAttribArray(0);
    
    animate(0.0);
  }
  
  void _initShaders() {
    String vsLine = """
precision mediump int;
precision mediump float;

attribute vec2  aPosition;

uniform mat4 uProjection;

void main() {
  gl_Position = uProjection * vec4(aPosition, 0.0, 1.0);
}
    """;
    
    String fsLine = """
precision mediump int;
precision mediump float;

void main() {
  gl_FragColor = vec4(0.0, 0.0, 0.0, 1.0);
}
    """;
    
    _lineShader = new Shader(_gl, vsLine, fsLine, {'aPosition': 0});

    String vsFill = """
precision mediump int;
precision mediump float;

attribute vec2  aPosition;
attribute float aColor;

uniform mat4  uProjection;

varying vec4  vColor;

const float dim   = 0.8;
const float brt   = 1.0;
const vec4 red    = vec4(brt, dim, dim, 1.0);
const vec4 yellow = vec4(brt, brt, dim, 1.0);
const vec4 green  = vec4(dim, brt, dim, 1.0);

void main() {
  gl_Position = uProjection * vec4(aPosition, 0.0, 1.0);
  if (aColor == 0.0)         vColor = red;
  else if (aColor == 1.0)    vColor = yellow;
  else                       vColor = green;
}
    """;
    
    String fsFill = """
precision mediump int;
precision mediump float;

varying vec4 vColor;

void main() {
  gl_FragColor = vColor;
}
    """;
    
    _fillShader = new Shader(_gl, vsFill, fsFill, {'aPosition': 0});
    
  }
  
  void animate(double time) {
    var lines = new List<Vector2>();
    var fills = new List<Vector3>();
    
    // Add a box
    lines.add(new Vector2(-1.0, -1.0));
    lines.add(new Vector2( 1.0, -1.0));
    lines.add(new Vector2( 1.0, -1.0));
    lines.add(new Vector2( 1.0,  1.0));
    lines.add(new Vector2( 1.0,  1.0));
    lines.add(new Vector2(-1.0,  1.0));
    lines.add(new Vector2(-1.0,  1.0));
    lines.add(new Vector2(-1.0, -1.0));
    
    Matrix4 circleMat = new Matrix4.identity();
    circleMat.scale(1.0, 1.0, 1.0);
    circleMat.rotateX(time / 10000.0);
    circleMat.rotateY(time / 11000.0);
    Matrix4 invCircleMat = new Matrix4.copy(circleMat)..invert();
    
    Vector3 unproject(double x, double y) {
      var dist = new Vector3(x, y, 0.0).dot(circleMat.forward) /
                 new Vector3(0.0, 0.0, 1.0).dot(circleMat.forward);
      var pt = new Vector4(x, y, dist, 1.0);
      Vector4 unproj = invCircleMat * pt;
      return unproj.xyz;
    }
    
    subDiv(double l, double r, double b, double t, int n, int minn) { 
      addQuad(double color) {
        fills.add(new Vector3(l, b, color));
        fills.add(new Vector3(r, b, color));
        fills.add(new Vector3(l, t, color));
        fills.add(new Vector3(r, t, color));
        fills.add(new Vector3(l, t, color));
        fills.add(new Vector3(r, b, color));
      }

      if (n <= 0) {
        //addQuad(1.0);
        return;
      }
      
      if (minn <= 0) {
        var corners = new List<Vector3>();
        corners.add(unproject(b, l));
        corners.add(unproject(b, r));
        corners.add(unproject(t, l));
        corners.add(unproject(t, r));

        // If some but not all corners are inside, this square needs subdivision
        int nIn = corners.fold(0, (count, elem) => count + ((elem.length2 <= 1.0)?1:0));
        
        bool edgeIntersect = false;
        if (nIn == 0) {
          // If any of the edges cross the circle (twice), this square needs subdivision.
          checkEdge(Vector3 pt1, Vector3 pt2) {
            // distance(x=a+tn, [0,0]) = ||a - (a.n)n||
            var n = pt2-pt1;
            var segL = n.length;
            n /= segL;  // Normalize
            var back = pt1.dot(n);
            var dist = (pt1 - n * back).length2;
            
            return (dist < 1.0) && (back <= 0.0) && (-back <= segL);
          }
          if (checkEdge(corners[0], corners[1]) ||
              checkEdge(corners[1], corners[2]) ||
              checkEdge(corners[2], corners[3]) ||
              checkEdge(corners[3], corners[0])) {
            edgeIntersect = true;
          } else {
            addQuad(0.0);
            return;
          }
        }
        
        if (nIn == 4) {
          addQuad(2.0);
          return;
        }
        
      }
      
      double mx = (l + r) / 2.0;
      double my = (b + t) / 2.0;
      
      lines.add(new Vector2(l, my));
      lines.add(new Vector2(r, my));
      lines.add(new Vector2(mx, b));
      lines.add(new Vector2(mx, t));
            
      subDiv(l, mx, b, my, n-1, minn-1);
      subDiv(mx, r, b, my, n-1, minn-1);
      subDiv(mx, r, my, t, n-1, minn-1);
      subDiv(l, mx, my, t, n-1, minn-1);
    };
    
    subDiv(-1.0, 1.0, -1.0, 1.0, 10, 1);
    
    var list = new Vector2List.fromList(lines);
    _nLines = list.length;
    _gl.bindBuffer(webgl.ARRAY_BUFFER, _vboLines);
    _gl.bufferDataTyped(webgl.ARRAY_BUFFER, list.buffer, webgl.DYNAMIC_DRAW);

    list = new Vector3List.fromList(fills);
    _nFills = list.length;
    _gl.bindBuffer(webgl.ARRAY_BUFFER, _vboFills);
    _gl.bufferDataTyped(webgl.ARRAY_BUFFER, list.buffer, webgl.DYNAMIC_DRAW);
  }
  
  void render() {
    _gl.clear(webgl.COLOR_BUFFER_BIT);
    
    _fillShader.use();
    _gl.bindBuffer(webgl.ARRAY_BUFFER, _vboFills);
    _gl.vertexAttribPointer(0, 2, webgl.FLOAT, false, 12, 0);
    _gl.vertexAttribPointer(1, 1, webgl.FLOAT, false, 12, 8);
    _gl.enableVertexAttribArray(0);
    _gl.enableVertexAttribArray(1);
    _gl.drawArrays(webgl.TRIANGLES, 0, _nFills);

    _lineShader.use();
    _gl.bindBuffer(webgl.ARRAY_BUFFER, _vboLines);
    _gl.vertexAttribPointer(0, 2, webgl.FLOAT, false, 0, 0);
    _gl.enableVertexAttribArray(0);
    _gl.drawArrays(webgl.LINES, 0, _nLines);
  }
}



var scene;
void main() {
  var canvas = document.querySelector("#glCanvas");
  scene = new CircleScene(canvas);
  
  window.animationFrame
    ..then((time) => animate(time));
}

void animate(double time) {
  scene.animate(time);
  scene.render();
  
  window.animationFrame
    ..then((time) => animate(time));
  
}
