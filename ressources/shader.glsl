#version 430

in vec2 fragTexCoord;
out vec4 finalColor;

uniform float ratio;
uniform vec3 cameraForward = vec3 (1., 0., 0.);
uniform vec3 cameraRight = vec3 (0., 1., 0.);
uniform vec3 cameraUp = vec3 (0., 0., 1.);
uniform vec3 position = vec3 (0., 0., -2.0);
uniform int n;
uniform float fov = 1.;

layout(std430, binding = 0) buffer MyBuffer {
    float data[];
};

bool outsideBox(vec3 currentVoxel) {
    return any(lessThan(currentVoxel, vec3 (0.))) || any(greaterThan(currentVoxel, vec3 (float (n-1))));
}

bool getVoxel(vec3 currentVoxel) {
    return  
    // all(lessThan(currentVoxel, vec3 (30.))) && all(greaterThan(currentVoxel, vec3 (1.))); 
    (sqrt((currentVoxel.x-16.)*(currentVoxel.x-16.) + (currentVoxel.y-16.)*(currentVoxel.y-16.) + (currentVoxel.z-16.)*(currentVoxel.z-16.)) < 10) || all(equal(currentVoxel, vec3 (31.)));
}

void main()
{
    vec2 uv = fragTexCoord;
    // data[0] += 2; syntax example
    uv *= 2.0;
    uv -= 1.;
    uv.x *= ratio;

    vec3 ray = normalize(cameraForward + uv.x*cameraRight*fov + uv.y*cameraUp*fov);
    vec3 pos = position;
    vec3 invRay;
    invRay.x = ray.x!=0 ? 1./ray.x : 0.;
    invRay.y = ray.y!=0 ? 1./ray.y : 0.;
    invRay.z = ray.z!=0 ? 1./ray.z : 0.;

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

    if(any(lessThan(pos, vec3 (0.))) || any(greaterThan(pos, vec3 (float (n))))) {
        pos += ray*tmin;
    }

    vec3 stepVect = sign(ray);
    vec3 absInvRay = abs(invRay);
    vec3 currentVoxel = floor(pos+vec3(0.0001)*stepVect);
    
    vec3 nextVoxelBoundary = (currentVoxel+stepVect)*1.;
    vec3 tMax = (nextVoxelBoundary - pos)*invRay;

    vec3 tDelta = 1.*stepVect*invRay;

    while(true) {
        if (outsideBox(currentVoxel)) {
            finalColor = vec4(0., 0., 0., 1.);
            return;
        }
        if (getVoxel(currentVoxel)) {
            finalColor = vec4(currentVoxel / float(n), 1.);
            return;
        }
        if (tMax.x < tMax.y) {
            if (tMax.x < tMax.z) {
                currentVoxel.x += stepVect.x;
                tMax.x += tDelta.x;
            } else {
                currentVoxel.z += stepVect.z;
                tMax.z += tDelta.z;
            }
        } else {
            if (tMax.y < tMax.z) {
                currentVoxel.y += stepVect.y;
                tMax.y += tDelta.y;
            } else {
                currentVoxel.z += stepVect.z;
                tMax.z += tDelta.z;
            }
        }
    }
    finalColor = vec4(0., 0., 0., 1.);
    return;
}