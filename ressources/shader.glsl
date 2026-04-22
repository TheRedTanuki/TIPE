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
    int index = coord.x + n*coord.y + n*n*coord.z;
    return int((data[index/4] >> (index%4)*8) & uint(255))-127;
}

float poly3(vec4 c, float t) {
    return c.w*t*t*t + c.z*t*t + c.y*t + c.x;
}

bool intersectVoxel(vec3 voxel, ivec3 voxelInt, vec3 rayOrigin, vec3 rayDir, float tSegment)
{
    vec3 voxelWorld = startPoint + voxel * voxelSize;

    vec3 localOrigin = (rayOrigin - voxelWorld) / voxelSize;
    vec3 localDir    = (rayDir * tSegment) / voxelSize;

    float scale = sqrt(2)/127;
    float s000 = float (getValue(voxelInt))*scale;
    float s100 = float (getValue(voxelInt + ivec3(1, 0, 0)))*scale;
    float s010 = float (getValue(voxelInt + ivec3(0, 1, 0)))*scale;
    float s110 = float (getValue(voxelInt + ivec3(1, 1, 0)))*scale;
    float s001 = float (getValue(voxelInt + ivec3(0, 0, 1)))*scale;
    float s101 = float (getValue(voxelInt + ivec3(1, 0, 1)))*scale;
    float s011 = float (getValue(voxelInt + ivec3(0, 1, 1)))*scale;
    float s111 = float (getValue(voxelInt + ivec3(1, 1, 1)))*scale;

    float a = s101 - s001;
    float k0 = s000;
    float k1 = s100 - s000;
    float k2 = s010 - s000;
    float k3 = s110 - s010 - k1;
    float k4 = k0 - s001;
    float k5 = k1 - a;
    float k6 = k2 - (s011 - s001);
    float k7 = k3 - (s111 - s011 - a);

    float m0 = localOrigin.x * localOrigin.y;
    float m1 = localDir.x * localDir.y;
    float m2 = localOrigin.x * localDir.y + localOrigin.y * localDir.x;
    float m3 = k5*localOrigin.z - k1;
    float m4 = k6*localOrigin.z - k2;
    float m5 = k7*localOrigin.z - k3;

    // Intersection between the suface and the ray : f(t) = c3*t³ +  c2*t² + c1*t + c0, f(t) = 0 //

    float c0 = (k4*localOrigin.z - k0) + localOrigin.x*m3 + localOrigin.y*m4 + m0*m5;

    float c1 = localDir.x*m3 + localDir.y*m4 + m2*m5 +
               localDir.z*(k4 + k5*localOrigin.x + k6*localOrigin.y + k7*m0);

    float c2 = m1*m5 + localDir.z*(k5*localDir.x + k6*localDir.y + k7*m2);

    float c3 = k7*m1*localDir.z;

    // Solving the equation //
    // f'(t) = 3*c3*t² + 2*c2*t + c1
    // find the locals extrema (if they exist) : f'(t) = 0

    // critical cases
    if (abs(c3) < 1e-6) {
        if (abs(c2) < 1e-6) {
            if (abs(c1) < 1e-6) return (c0 == 0.);
            float t = -c0 / c1;
            return t >= 0. && t <= 1.;
        }
        float d = c1*c1 - 4.*c2*c0;
        if (d < 0.) return false;
        float t1 = (-c1 - sqrt(d))/(2.*c2);
        float t2 = (-c1 + sqrt(d))/(2.*c2);
        return (t1>=0. && t1<=1.) || (t2>=0. && t2<=1.);
    }


    float f0 = c0;
    float f1 = c0 + c1 + c2 + c3;

    float delta = 4.0*c2*c2 - 12.0*c3*c1;
    float b0;
    float b1;

    if (delta >= 0.0) {
        float s = sqrt(delta);
        float t1 = (-2.0*c2 - s)/(6.0*c3);
        float t2 = (-2.0*c2 + s)/(6.0*c3);
        vec4 c = vec4(c0, c1, c2, c3);

        if (t1>0.0 && t1<1.0) {
            float ft1 = poly3(c,t1);
            if (min(f0, ft1)<= 0. && max(f0, ft1)>= 0.) {
                b0 = f0;
                b1 = ft1;
            }
            else if (t2>0.0 && t2<1.0) {
                float ft2 = poly3(c,t2);
                if (min(ft1, ft2)<= 0. && max(ft1, ft2)>= 0.) {
                    b0 = ft1;
                    b1 = ft2;
                }
                else if (min(ft2, f1)<= 0. && max(ft2, f1)>= 0.) {
                    b0 = ft2;
                    b1 = f1;
                }
                else {
                    return false;
                }
            }
            else if (min(ft1, f1)<= 0. && max(ft1, f1)>= 0.) {
                b0 = ft1;
                b1 = f1;
            }
            else {
                return false;
            }
        }
        else if (t2>0.0 && t2<1.0) {
            float ft2 = poly3(c,t2);
            if (min(f0, ft2)<= 0. && max(f0, ft2)>= 0.) {
                b0 = f0;
                b1 = ft2;
            }
            else if (min(ft2, f1)<= 0. && max(ft2, f1)>= 0.) {
                b0 = ft2;
                b1 = f1;
            }
            else {
                return false;
            }
        }
        else if (min(f0, f1)<= 0. && max(f0, f1)>= 0.) {
            b0 = f0;
            b1 = f1;
        }
        else {
            return false;
        }
    }
    else if (min(f0, f1)<= 0. && max(f0, f1)>= 0.) {
        b0 = f0;
        b1 = f1;
    }
    else {
        return false;
    }

    return true;
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

    float t = max(tmin, 0.0);
    pos += ray*t;

    vec3 stepVect = sign(ray);
    ivec3 stepVectInt = ivec3(stepVect);
    vec3 currentVoxel = floor((pos-startPoint)/voxelSize + ray*1e-4*voxelSize);
    ivec3 currentVoxelInt = ivec3(currentVoxel);

    vec3 nextVoxelBoundary = (currentVoxel + max(stepVect, vec3(0.0)))*voxelSize + startPoint;
    vec3 tMax = (nextVoxelBoundary-position)*invRay;
    vec3 tDelta = abs(invRay)*voxelSize;

    for(int i = 0; i<256; i++) {
        if(!inBoundaries(currentVoxel)) {
            break;
        }
        float tNext = min(tMax.x, min(tMax.y, tMax.z));
        if (intersectVoxel(currentVoxel, currentVoxelInt, position + t*ray, ray, tNext-t)) {
            finalColor = vec4(currentVoxel/(float(n-1)), 1.);
            return;
        }
        if(tMax.x < tMax.y) {
            if(tMax.x < tMax.z) {
                currentVoxel.x += stepVect.x;
                currentVoxelInt.x += stepVectInt.x;
                t = tMax.x;
                tMax.x += tDelta.x;
            }
            else {
                currentVoxel.z += stepVect.z;
                currentVoxelInt.z += stepVectInt.z;
                t = tMax.z;
                tMax.z += tDelta.z;
            }
        }
        else {
            if(tMax.y < tMax.z) {
                currentVoxel.y += stepVect.y;
                currentVoxelInt.y += stepVectInt.y;
                t = tMax.y;
                tMax.y += tDelta.y;
            }
            else {
                currentVoxel.z += stepVect.z;
                currentVoxelInt.z += stepVectInt.z;
                t = tMax.z;
                tMax.z += tDelta.z;
            }
        }
    }
    finalColor = vec4(0., 0., 0., 1.);
    return;
}