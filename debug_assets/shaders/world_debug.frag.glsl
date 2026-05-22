#version 330

in vec2 fragTexCoord;
in vec4 fragColor;
out vec4 finalColor;

uniform sampler2D texture0;
uniform vec4 colDiffuse;

void main() {
    vec4 color = texture2D(texture0, fragTexCoord);

    vec2 segment_uv = fragTexCoord * 100.0;
    vec2 grid = fract(segment_uv);

    vec2 dist = min(grid, 1.0 - grid);
    vec2 fw = fwidth(segment_uv);

    // If a pixel covers more than ~half a cell, don't draw lines (would be noise)
    vec2 mask = step(fw, vec2(0.5));

    vec2 lineAA = (1.0 - smoothstep(vec2(0.0), fw * 1.5, dist)) * mask;
    float line = max(lineAA.x, lineAA.y);

    finalColor = mix(color, vec4(0.0, 0.0, 0.0, 1.0), line);
}
