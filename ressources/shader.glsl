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

layout(std430, binding = 0) buffer MyBuffer {
    float data[];
};

bool inBoundaries(vec3 pos) {
    return all(greaterThanEqual(pos, vec3 (0.))) && all(lessThanEqual(pos, vec3 (float (n-1))));
}

bool getVoxel(vec3 voxelPos) {
    return (voxelPos.x-16.)*(voxelPos.x-16.) + (voxelPos.y-16.)*(voxelPos.y-16.) + (voxelPos.z-16.)*(voxelPos.z-16.) < 100;
}

void main() {
    vec2 uv = fragTexCoord;
    // data[0] += 2; syntax example
    uv *= 2.0;
    uv -= 1.;
    uv.x *= ratio;


    vec3 ray = normalize(cameraForward + uv.x*cameraRight*fov + uv.y*cameraUp*fov);
    vec3 pos = position;
    vec3 invRay = 1./ray;

    vec3 t0 = (vec3(0.)-pos) * invRay;
    vec3 t1 = (vec3(float(n)) - pos) * invRay;

    vec3 tmin3 = min(t0, t1);
    vec3 tmax3 = max(t0, t1);

    float tmin = max(max(tmin3.x, tmin3.y), tmin3.z);
    float tmax = min(min(tmax3.x, tmax3.y), tmax3.z);

    if(tmax < 0. || tmin > tmax){
        finalColor = vec4(0., 0., 0., 1.);
        return;
    }

    if(any(lessThan(pos, vec3 (0.))) || any(greaterThanEqual(pos, vec3 (float (n))))) {
        pos += ray*tmin;
    }

    vec3 stepVect = sign(ray);
    vec3 currentVoxel = floor(pos+ray*1e-4);
    vec3 nextBoundary = currentVoxel+max(stepVect, vec3(0.0));
    vec3 t = (nextBoundary-pos)*invRay;
    vec3 tDelta = abs(invRay);

    while(true) {
        if(!inBoundaries(currentVoxel)) {
            finalColor = vec4(0., 0., 0., 1.);
            return;
        }
        if(getVoxel(currentVoxel)) {
            finalColor = vec4(currentVoxel/float(n), 1.);
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