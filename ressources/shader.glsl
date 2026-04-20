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

int getValue(ivec3 coord) {
    int index = coord.x+n*coord.y+n*n*coord.z;
    return int((data[index/4] >> (index%4)*8) & uint(255))-127;
}

float poly3(vec4 c, float t) {
    return c.w*t*t*t + c.z*t*t + c.y*t + c.x;
}

bool getVoxel2(vec3 voxelPos, float t, vec3 rayOrigin, vec3 rayDirection) {
    vec3 rayLocalOrigin = rayOrigin+t*rayDirection-voxelPos; // false when rayDirection is negative TODO : correct it
    ivec3 coord = ivec3(voxelPos);
    float divideFactor = sqrt(2)/128;
    float s000 = float (getValue(coord))*divideFactor;
    float s100 = float (getValue(coord + ivec3(1, 0, 0)))*divideFactor;
    float s010 = float (getValue(coord + ivec3(0, 1, 0)))*divideFactor;
    float s110 = float (getValue(coord + ivec3(1, 1, 0)))*divideFactor;
    float s001 = float (getValue(coord + ivec3(0, 0, 1)))*divideFactor;
    float s101 = float (getValue(coord + ivec3(1, 0, 1)))*divideFactor;
    float s011 = float (getValue(coord + ivec3(0, 1, 1)))*divideFactor;
    float s111 = float (getValue(coord + ivec3(1, 1, 1)))*divideFactor;

    float a = s101 - s001;
    float k0 = s000;
    float k1 = s100 - s000;
    float k2 = s010 - s000;
    float k3 = s110 - s010 - k1;
    float k4 = k0 - s001;
    float k5 = k1 - a;
    float k6 = k2 - (s011 - s001);
    float k7 = k3 - (s111 - s011 - a);

    float m0 = rayLocalOrigin.x*rayLocalOrigin.y;
    float m1 = rayDirection.x*rayDirection.y;
    float m2 = rayLocalOrigin.x*rayDirection.y + rayLocalOrigin.y*rayDirection.x;
    float m3 = k5*rayLocalOrigin.z-k1;
    float m4 = k6*rayLocalOrigin.z-k2;
    float m5 = k7*rayLocalOrigin.z-k3;

    // Intersection between the suface and the ray : f(t) = c3*t³ +  c2*t² + c1*t + c0, f(t) = 0 //

    float c0 = (k4*rayLocalOrigin.z-k0) + rayLocalOrigin.x*m3 + rayLocalOrigin.y*m4 + m0*m5;
    float c1 = rayDirection.x*m3 + rayDirection.y*m4 + m2*m5 + rayDirection.z*(k4 + k5*rayLocalOrigin.x + k6*rayLocalOrigin.y + k7*m0);
    float c2 = m1*m5 + rayDirection.z*(k5*rayDirection.x + k6*rayDirection.y + k7*m2);
    float c3 = k7*m1*rayDirection.z;

    // Solving the equation //
    // f'(t) = 3*c3*t² + 2*c2*t + c1
    // find the locals extrema (if they exist) : f'(t) = 0
    float delta = 4*c2*c2 - 4*3*c3*c1; // delta = b² - 4ac
    vec4 c = vec4(c0, c1, c2, c3);
    float absMax;
    float absMin;
    if(delta >= 0.) {
        float t1 = clamp((-2*c2-sqrt(delta))/(2*3*c3), 0., 1.); // -b-sqrt(delta)/2a
        float t2 = clamp((-2*c2+sqrt(delta))/(2*3*c3), 0., 1.); // -b+sqrt(delta)/2a
        absMax = max(max(poly3(c, 0.), poly3(c, 1.)), max(poly3(c, t1), poly3(c, t2)));
        absMin = min(min(poly3(c, 0.), poly3(c, 1.)), min(poly3(c, t1), poly3(c, t2)));
    }
    else {
        absMax = max(poly3(c, 0.), poly3(c, 1.));
        absMin = min(poly3(c, 0.), poly3(c, 1.));
    }

    return (absMin <= 0.0 && absMax >= 0.0);
}

// print all data (not working)
/*void main() {
    vec2 uv = fragTexCoord;
    uv.x *= n*n;
    uv.y *= n;
    float val = (getValue(ivec3(int(uv.x)%n, int(uv.y), int(uv.x)/n))+127)/255;
    finalColor = vec4(vec3(val), 1.);
}*/

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
    vec3 tMax = (nextVoxelBoundary-(pos-startPoint))*invRay;
    float t = 0.;
    vec3 tDelta = abs(invRay)*voxelSize;

    for(int i = 0; i<256; i++) {
        if(!inBoundaries(currentVoxel)) {
            finalColor = vec4(0., 0., 0., 1.);
            return;
        }
        if (getVoxel2(currentVoxel, t, pos, ray)) {
            finalColor = vec4(currentVoxel/(float(n-1)), 1.);
            return;
        }
        if(tMax.x < tMax.y) {
            if(tMax.x < tMax.z) {
                currentVoxel.x += stepVect.x;
                tMax.x += tDelta.x;
                t = tMax.x;
            }
            else {
                currentVoxel.z += stepVect.z;
                tMax.z += tDelta.z;
                t = tMax.z;
            }
        }
        else {
            if(tMax.y < tMax.z) {
                currentVoxel.y += stepVect.y;
                tMax.y += tDelta.y;
                t = tMax.y;
            }
            else {
                currentVoxel.z += stepVect.z;
                tMax.z += tDelta.z;
                t = tMax.z;
            }
        }
    }
    finalColor = vec4(0., 0., 0., 1.);
    return;
}