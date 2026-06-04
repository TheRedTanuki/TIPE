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
uniform int newtonNMax = 5; // precision of t determination (increase for more precision)
uniform int mode;
uniform vec3 lightDir = normalize(vec3(1.0, 1.0, 1.0));

#define voxelSize brickSize / 8.0
#define invVoxelSize 8./brickSize

layout(std430, binding = 0) buffer bricksArray {
    uint bricks[];
};

layout(std430, binding = 1) buffer dataArray {
    uint data[];
};

bool inBoundaries(vec3 pos) {
    return all(greaterThanEqual(pos, vec3 (0.))) && all(lessThan(pos, vec3 (float(nBrick))));
}

bool inBrickBoundaries(vec3 voxelPos, vec3 brickPos) {
    ivec3 b = ivec3(brickPos);
    ivec3 boundary;
    boundary.x = b.x==nBrick-1 ? 7 : 8;
    boundary.y = b.y==nBrick-1 ? 7 : 8;
    boundary.z = b.z==nBrick-1 ? 7 : 8;
    return all(greaterThanEqual(ivec3(voxelPos), ivec3 (0))) && all(lessThan(ivec3(voxelPos), boundary));
}

uint getBrickValue(ivec3 pos) {
    return bricks[pos.x + nBrick*pos.y + nBrick*nBrick*pos.z];
}

bool getBrick(ivec3 pos) {
    return getBrickValue(pos)>>31!=0;
}

int getValue(uint offset, ivec3 localPos) {
    uint index = localPos.x + 8*localPos.y + 8*8*localPos.z;
    return int(data[(offset)*512 + index] & uint(255))-127;
}

int getVoxel(ivec3 voxel, ivec3 brick) {
    uint brickValue = getBrickValue(brick);
    if (brickValue>>31 != 0) {
        uint offset = brickValue&uint(((1<<31) - 1));
        return getValue(offset, voxel);
    }
    if (((brickValue>>30)&uint(1)) !=0) return -127; // brick is full
    return 127; // brick is empty
}

float poly3(vec4 c, float t) {
    return ((c.w*t + c.z)*t + c.y)*t + c.x;
}

float poly2(vec3 c, float t) {
    return (c.z*t + c.y)*t +c.x;
}

bool signDiff(float x1, float x2) {
    return x1*x2 <= 0.;
}

float lerp(float x, float a, float b) {
    return a + x*(b-a);
}

vec4 computeNormal(
    float s000,
    float s100,
    float s010,
    float s110,
    float s001,
    float s101,
    float s011,
    float s111,
    float t,
    vec3 localOrigin,
    vec3 localDir,
    vec3 rayDir
    ) {
    float x = localOrigin.x + localDir.x*t;
    float y = localOrigin.y + localDir.y*t;
    float z = localOrigin.z + localDir.z*t;

    float y0 = lerp(y, s100 - s000, s110 - s010);
    float y1 = lerp(y, s101 - s001, s111 - s011);
    float dx = lerp(z, y0, y1);

    float x0 = lerp(x, s010 - s000, s110 - s100);
    float x1 = lerp(x, s011 - s001, s111 - s101);
    float dy = lerp(z, x0, x1);

    x0 = lerp(x, s001 - s000, s101 - s100);
    x1 = lerp(x, s011 - s010, s111 - s110);
    float dz = lerp(y, x0, x1);
    return vec4(normalize(vec3(dx, dy, dz)), 1.);
}

vec4 intersectVoxel(vec3 voxel, vec3 brick, vec3 rayOrigin, vec3 rayDir, float tSegment) {
    ivec3 voxelInt = ivec3(voxel);
    ivec3 brickInt = ivec3(brick);
    vec3 voxelWorld = startPoint + voxel * voxelSize + brick * brickSize;

    vec3 localOrigin = (rayOrigin - voxelWorld) * invVoxelSize;
    vec3 localDir    = (rayDir * tSegment) * invVoxelSize;

    float scale = sqrt(2.0)/127.0;

    // Trilinear interpolation coefficients
    // if they are all in the same brick, manually compute each call (skip 7 redundant calls to brickArray)
    if(all(lessThan(voxelInt, vec3(7)))) {
        int brickValue = getBrickValue(brickInt);
        if (brickValue>>31==0) {
            int val = (((brickValue>>30)&uint(1)) !=0) ? -127 : 127;
            float res = val*scale;
            float s000 = res;
            float s100 = res;
            float s010 = res;
            float s110 = res;
            float s001 = res;
            float s101 = res;
            float s011 = res;
            float s111 = res;
        }
        else {
            uint offset = brickValue&uint(((1<<31) - 1));
            float s000 = getValue(offset, voxelInt); * scale;
            float s100 = float(getValue(offset, voxelInt + ivec3(1,0,0)))* scale;
            float s010 = float(getValue(offset, voxelInt + ivec3(0,1,0)))* scale;
            float s110 = float(getValue(offset, voxelInt + ivec3(1,1,0)))* scale;
            float s001 = float(getValue(offset, voxelInt + ivec3(0,0,1)))* scale;
            float s101 = float(getValue(offset, voxelInt + ivec3(1,0,1)))* scale;
            float s011 = float(getValue(offset, voxelInt + ivec3(0,1,1)))* scale;
            float s111 = float(getValue(offset, voxelInt + ivec3(1,1,1)))* scale;
        }
    }
    else {
        float s000 = float(getVoxel(voxelInt, brickInt)) * scale;
        float s100 = float(getVoxel((voxelInt + ivec3(1,0,0))&7, brickInt + ((voxelInt + ivec3(1,0,0))>>3))) * scale;
        float s010 = float(getVoxel((voxelInt + ivec3(0,1,0))&7, brickInt + ((voxelInt + ivec3(0,1,0))>>3))) * scale;
        float s110 = float(getVoxel((voxelInt + ivec3(1,1,0))&7, brickInt + ((voxelInt + ivec3(1,1,0))>>3))) * scale;
        float s001 = float(getVoxel((voxelInt + ivec3(0,0,1))&7, brickInt + ((voxelInt + ivec3(0,0,1))>>3))) * scale;
        float s101 = float(getVoxel((voxelInt + ivec3(1,0,1))&7, brickInt + ((voxelInt + ivec3(1,0,1))>>3))) * scale;
        float s011 = float(getVoxel((voxelInt + ivec3(0,1,1))&7, brickInt + ((voxelInt + ivec3(0,1,1))>>3))) * scale;
        float s111 = float(getVoxel((voxelInt + ivec3(1,1,1))&7, brickInt + ((voxelInt + ivec3(1,1,1))>>3))) * scale;
    }

    float maxVal = max(max(max(s000, s100), max(s010, s110)), max(max(s001, s101), max(s011, s111)));

    float minVal = min(min(min(s000, s100), min(s010, s110)), min(min(s001, s101), min(s011, s111)));

    if(minVal>0. || maxVal<0.) return vec4(0.);

    // Computing coefficients
    float a  = s101 - s001;
    float k1 = s100 - s000;
    float k2 = s010 - s000;
    float k3 = s110 - s010 - k1;
    float k4 = s000 - s001;
    float k5 = k1 - a;
    float k6 = k2 - (s011 - s001);
    float k7 = k3 - (s111 - s011 - a);

    float m0 = localOrigin.x * localOrigin.y;
    float m1 = localDir.x * localDir.y;
    float m2 = localOrigin.x * localDir.y + localOrigin.y * localDir.x;
    float m3 = k5*localOrigin.z - k1;
    float m4 = k6*localOrigin.z - k2;
    float m5 = k7*localOrigin.z - k3;

    // Cubic coefficients f(t) = c3*t^3 + c2*t^2 + c1*t + c0
    float c0 = (k4*localOrigin.z - s000) + localOrigin.x*m3 + localOrigin.y*m4 + m0*m5;
    float c1 = localDir.x*m3 + localDir.y*m4 + m2*m5 +
               localDir.z*(k4 + k5*localOrigin.x + k6*localOrigin.y + k7*m0);
    float c2 = m1*m5 + localDir.z*(k5*localDir.x + k6*localDir.y + k7*m2);
    float c3 = k7*m1*localDir.z;

    vec4 c = vec4(c0, c1, c2, c3);

    // Evaluate endpoints in 0 and 1
    float f0 = c0;
    float f1 = c0 + c1 + c2 + c3;

    // critical cases
    // please note that t is exact in these cases
    float tIntersect;
    if (abs(c3) < 1e-6) {
        if (abs(c2) < 1e-6) {
            if (abs(c1) < 1e-6) {
                if (abs(c0) < 1e-6) tIntersect = c0;
                else return vec4(0.);
            }
            float t = -c0 / c1;
            if (t >= 0. && t <= 1.) tIntersect = t;
            else return vec4(0.);
        }
        else {
            float d = c1*c1 - 4.*c2*c0;
            if (d < 0.) return vec4(0.);
            float t1 = (-c1 - sqrt(d))/(2.*c2);
            if (t1>=0. && t1<=1.) tIntersect = t1;
            else {
                float t2 = (-c1 + sqrt(d))/(2.*c2);
                if (t2>=0. && t2<=1.) tIntersect = t2;
                else return vec4(0.);
            }
        }
    }
    // normal cases
    else {
        // Find a bracket [ta, tb] that crosses 0
        bool hasRoot = false;
        float ta,tb;
        float tArray[4];
        int count = 0;

        tArray[count++] = 0.;

        float delta = 4.*c2*c2 - 12.*c3*c1;
        if (delta >= 0.) {
            float s = sqrt(delta);
            float t1 = (-2.*c2-s)/(6.*c3);
            float t2 = (-2.*c2+s)/(6.*c3);
            float t1Ordered = min(t1, t2);
            float t2Ordered = max(t1, t2);
            if (t1Ordered>0. && t1Ordered<1.) tArray[count++] = t1Ordered;
            if (t2Ordered>0. && t2Ordered<1.) tArray[count++] = t2Ordered;
        }
        tArray[count++] = 1.;

        for(int i = 0; i < count-1; i++) {
            float a = tArray[i];
            float b = tArray[i+1];

            float fa = poly3(c, a);
            float fb = poly3(c, b);

            if (signDiff(fa, fb)) {
                ta = a;
                tb = b;
                hasRoot = true;
                break;
            }
        }
        // if none -> no solutions
        if (!hasRoot) return vec4(0.);

        // if one -> determine solution with Newton's method
        float t = 0.5 * (ta + tb); // starting point
        vec3 d = vec3(3.0*c3, 2.0*c2, c1);

        for (int i = 0; i < newtonNMax; i++) {
            float f = poly3(c, t);
            float df = poly2(d, t);

            float tNew;
            if (abs(df) > 1e-6) {
                tNew = t - f/df;
                if (tNew < ta || tNew > tb) {
                    tNew = 0.5 * (ta + tb);
                }
            } else {
                tNew = 0.5 * (ta + tb);
            }

            float fNew = poly3(c, tNew);

            if (fNew > 0.0)
                tb = tNew;
            else
                ta = tNew;

            t = tNew;
        }
        tIntersect = t;
    }
    if (mode == 1) return computeNormal(s000, s100, s010, s110, s001, s101, s011, s111, tIntersect, localOrigin, localDir, rayDir);
    if (mode == 2) return vec4((voxel+brick*8.)/float(nBrick*8.), 1.);
    if (mode == 3) {
        vec4 color = computeNormal(s000, s100, s010, s110, s001, s101, s011, s111, tIntersect, localOrigin, localDir, rayDir);
        return vec4(vec3((dot(color.xyz, lightDir)+1.)/2.), 1.0);
    }
    return vec4(vec3(tIntersect), 1.);
}

void main() {
    vec3 endPoint = startPoint+vec3((nBrick)*brickSize-1.*voxelSize);
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
    vec3 currentBrick = floor((pos-startPoint)/brickSize + ray*1e-4);

    vec3 nextBrickBoundary = (currentBrick + max(stepVect, vec3(0.0)))*brickSize + startPoint;
    vec3 tMaxBrick = (nextBrickBoundary-position)*invRay;
    vec3 tDeltaBrick = abs(invRay)*brickSize;

    for(int i = 0; i<256; i++) {
        if(!inBoundaries(currentBrick)) {
            break;
        }
        if(getBrick(ivec3(currentBrick))) {
            float tVoxel = 0.;
            vec3 localOrigin = currentBrick*brickSize + startPoint;
            vec3 localPos = position + t*ray - localOrigin;
            vec3 currentVoxel = floor((localPos) * invVoxelSize + ray*1e-3);

            vec3 nextVoxelBoundary = (currentVoxel + max(stepVect, vec3(0.)))*voxelSize;
            vec3 tMaxVoxel = (nextVoxelBoundary-localPos)*invRay;
            vec3 tDeltaVoxel = abs(invRay)*voxelSize;

            for(int j = 0; j<24; j++) {
                if(!inBrickBoundaries(currentVoxel, currentBrick)) {
                    break;
                }
                float tNext = min(tMaxVoxel.x, min(tMaxVoxel.y, tMaxVoxel.z));
                vec4 color = intersectVoxel(currentVoxel, currentBrick, position + ray*(t+tVoxel), ray, tNext - tVoxel);
                if(color!=vec4(0.)) {
                    finalColor = color;
                    return;
                }

                if(tMaxVoxel.x < tMaxVoxel.y) {
                    if(tMaxVoxel.x < tMaxVoxel.z) {
                        currentVoxel.x += stepVect.x;
                        tVoxel = tMaxVoxel.x;
                        tMaxVoxel.x += tDeltaVoxel.x;
                    }
                    else {
                        currentVoxel.z += stepVect.z;
                        tVoxel = tMaxVoxel.z;
                        tMaxVoxel.z += tDeltaVoxel.z;
                    }
                }
                else {
                    if(tMaxVoxel.y < tMaxVoxel.z) {
                        currentVoxel.y += stepVect.y;
                        tVoxel = tMaxVoxel.y;
                        tMaxVoxel.y += tDeltaVoxel.y;
                    }
                    else {
                        currentVoxel.z += stepVect.z;
                        tVoxel = tMaxVoxel.z;
                        tMaxVoxel.z += tDeltaVoxel.z;
                    }
                }
            }

        }
        if(tMaxBrick.x < tMaxBrick.y) {
            if(tMaxBrick.x < tMaxBrick.z) {
                currentBrick.x += stepVect.x;
                t = tMaxBrick.x;
                tMaxBrick.x += tDeltaBrick.x;
            }
            else {
                currentBrick.z += stepVect.z;
                t = tMaxBrick.z;
                tMaxBrick.z += tDeltaBrick.z;
            }
        }
        else {
            if(tMaxBrick.y < tMaxBrick.z) {
                currentBrick.y += stepVect.y;
                t = tMaxBrick.y;
                tMaxBrick.y += tDeltaBrick.y;
            }
            else {
                currentBrick.z += stepVect.z;
                t = tMaxBrick.z;
                tMaxBrick.z += tDeltaBrick.z;
            }
        }
    }
    finalColor = vec4(0., 0., 0., 1.);
    return;
}