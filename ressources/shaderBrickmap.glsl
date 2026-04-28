#version 430

in vec2 fragTexCoord
out vec4 finalColor

uniform float ratio;
uniform vec3 cameraForward = vec3 (1., 0., 0.);
uniform vec3 cameraRight = vec3 (0., 1., 0.);
uniform vec3 cameraUp = vec3 (0., 0., 1.);
uniform vec3 position = vec3 (0., 0., 0.);
uniform int n;
uniform float fov = 1.;
uniform float voxelSize = 1.;
uniform vec3 startPoint = vec3 (0., 0., 0.);
uniform int newtonNMax = 15; // precision of t determination (increase for more precision)
uniform int mode;
uniform vec3 lightDir = normalize(vec3(1.0, 1.0, 1.0));

layout(std430, binding = 0) buffer bricksArray {
    uint bricks[];
};

layout(std430, binding = 1) buffer dataArray {
    uint data[];
};

void main() {
    vec3 endPoint = startPoint+vec3((n-1)*voxelSize);
    vec2 uv = fragTexCoord;
    uv *= 2.0;
    uv -= 1.;
    uv.x *= ratio;

    vec3 ray = normalize(cameraForward + uv.x*cameraRight*fov + uv.y*cameraUp*fov);
    vec3 pos = position;
    vec3 invRay = 1./ray;

    vec3 t0 = (startPoint-pos) * invRay;
    vec3 t1 = (endPoint - pos) * invRay;

    vec3 tmin3 = min(t0, t1);
    vec3 tmax3 = max(t0, t1);

    float tmin = max(max(tmin3.x, tmin3.y), tmin3.z);
    float tmax = min(min(tmax3.x, tmax3.y), tmax3.z);

    if(tmax < 0. || tmin > tmax){
        finalColor = vec4(0., 0., 0., 1.);
        return;
    }

    float t = max(tmin, 0.0);
    pos += ray*t;

    finalColor = vec4(0., 0., 0., 1.0);
    return;
}