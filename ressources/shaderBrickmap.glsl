#version 430

in vec2 fragTexCoord;
out vec4 finalColor;

uniform float ratio;
uniform vec3 cameraForward = vec3 (1., 0., 0.);
uniform vec3 cameraRight = vec3 (0., 1., 0.);
uniform vec3 cameraUp = vec3 (0., 0., 1.);
uniform vec3 position = vec3 (0., 0., 0.);
uniform int nBrick;
uniform float fov = 1.;
uniform float brickSize = 8.;
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

bool inBoundaries(vec3 pos) {
    return all(greaterThanEqual(pos, vec3 (0.))) && all(lessThan(pos, vec3 (float(nBrick-1))));
}

uint getBrickValue(ivec3 pos) {
    return bricks[pos.x + nBrick*pos.y + nBrick*nBrick*pos.z];
}

bool getBrick(ivec3 pos) {
    return getBrickValue(pos)>>31!=0;
}

uint getValue(uint offset, ivec3 localPos) {
    return data[offset*128 + localPos.x + 8*localPos.y + 8*8*localPos.z];
}

bool getVoxel(ivec3 voxel) {
    ivec3 brickPos = voxel/8;
    ivec3 localPos = voxel%ivec3(8);
    uint res = getBrickValue(brickPos);
    if (res>>31!=0) {
        uint offset = res&(1<<31 - 1);
        return getValue(offset, localPos)!=0;
    }
    if (((res>>30)&1) !=0) return false; // brick is full
    return false; // brick is empty
}

void main() {
    vec3 endPoint = startPoint+vec3((nBrick-1)*brickSize);
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

    vec3 stepVect = sign(ray);
    ivec3 stepVectInt = ivec3(stepVect);
    vec3 currentBrick = floor((pos-startPoint)/brickSize + ray*1e-4*brickSize);

    vec3 nextBrickBoundary = (currentBrick + max(stepVect, vec3(0.0)))*brickSize + startPoint;
    vec3 tMax = (nextBrickBoundary-position)*invRay;
    vec3 tDelta = abs(invRay)*brickSize;

    for(int i = 0; i<256; i++) {
        if(!inBoundaries(currentBrick)) {
            break;
        }
        float tNext = min(tMax.x, min(tMax.y, tMax.z));
        if (getBrick(ivec3(currentBrick))) {
            finalColor = vec4(1., 1., 1., 1.);
            return;
        }
        if(tMax.x < tMax.y) {
            if(tMax.x < tMax.z) {
                currentBrick.x += stepVect.x;
                t = tMax.x;
                tMax.x += tDelta.x;
            }
            else {
                currentBrick.z += stepVect.z;
                t = tMax.z;
                tMax.z += tDelta.z;
            }
        }
        else {
            if(tMax.y < tMax.z) {
                currentBrick.y += stepVect.y;
                t = tMax.y;
                tMax.y += tDelta.y;
            }
            else {
                currentBrick.z += stepVect.z;
                t = tMax.z;
                tMax.z += tDelta.z;
            }
        }
    }

    finalColor = vec4(1., 0., 0., 1.0);
    return;
}