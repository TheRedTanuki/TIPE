#version 430

in vec2 fragTexCoord;
out vec4 finalColor;

uniform float ratio;
uniform vec3 cameraForward = vec3 (1., 0., 0.);
uniform vec3 cameraRight = vec3 (0., 1., 0.);
uniform vec3 cameraUp = vec3 (0., 0., 1.);
uniform vec3 position = vec3 (0., 0., 0.);
uniform int nBricks;
uniform float fov = 1.;
uniform float brickSize = 1.;
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

uint getBrick(ivec3 pos) {
    return bricks[pos.x + nBricks*pos.y + nBricks*nBricks*pos.z];
}

uint getValue(uint offset, ivec3 localPos) {
    return data[offset*128 + localPos.x + 8*localPos.y + 8*8*localPos.z];
}

bool getVoxel(ivec3 voxel) {
    ivec3 brickPos = voxel/8;
    ivec3 localPos = voxel%ivec3(8);
    uint res = getBrick(brickPos);
    if (res>>31!=0) {
        uint offset = res&(1<<31 - 1);
        return getValue(offset, localPos)!=0;
    }
    if (((res>>30)&1) !=0) return false; // brick is full
    return false; // brick is empty
}

void main() {
    vec3 endPoint = startPoint+vec3((nBricks-1)*brickSize);
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