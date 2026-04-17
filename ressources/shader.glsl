#version 430

in vec2 fragTexCoord;
out vec4 finalColor;

uniform float ratio;
uniform vec3 cameraForward = vec3 (1., 0., 0.);
uniform vec3 cameraRight = vec3 (0., 1., 0.);
uniform vec3 cameraUp = vec3 (0., 0., 1.);
uniform vec3 position = vec3 (0., 0., 0.);
uniform int n;
uniform float fov = 1.;
uniform float voxelSize = 1.;
uniform vec3 startPoint = vec3 (0., 0., 0.);

layout(std430, binding = 0) buffer MyBuffer {
    uint data[];
};

bool inBoundaries(vec3 pos) {
    return all(greaterThanEqual(pos, vec3 (0.))) && all(lessThan(pos, vec3 (float(n-1))));
}

bool getVoxel(vec3 voxelPos) {
    ivec3 co = ivec3(voxelPos);
    int index = co.x+n*co.y+n*n*co.z;
    return ((data[index/4] >> (index%4)*8) & uint(255))!=0;
}

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

    if(any(lessThan(pos, startPoint)) || any(greaterThanEqual(pos, endPoint))) {
        pos += ray*tmin;
    }

    vec3 stepVect = sign(ray);
    vec3 currentVoxel = floor((pos-startPoint)/voxelSize+ray*1e-4);
    vec3 nextVoxelBoundary = (currentVoxel+max(stepVect, vec3(0.0)))*voxelSize;
    vec3 t = (nextVoxelBoundary-(pos-startPoint))*invRay;
    vec3 tDelta = abs(invRay)*voxelSize;

    for(int i = 0; i<256; i++) {
        if(!inBoundaries(currentVoxel)) {
            finalColor = vec4(0., 0., 0., 1.);
            return;
        }
        if(getVoxel(currentVoxel)) {
            finalColor = vec4(currentVoxel/(float(n-1)), 1.);
            return;
        }
        if(t.x < t.y) {
            if(t.x < t.z) {
                currentVoxel.x += stepVect.x;
                t.x += tDelta.x;
            }
            else {
                currentVoxel.z += stepVect.z;
                t.z += tDelta.z;
            }
        }
        else {
            if(t.y < t.z) {
                currentVoxel.y += stepVect.y;
                t.y += tDelta.y;
            }
            else {
                currentVoxel.z += stepVect.z;
                t.z += tDelta.z;
            }
        }
    }
    finalColor = vec4(0., 0., 0., 1.);
    return;
}