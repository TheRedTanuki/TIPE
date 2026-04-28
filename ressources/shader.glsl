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
uniform int newtonNMax = 15; // precision of t determination (increase for more precision)
uniform int mode;
uniform vec3 lightDir = normalize(vec3(1.0, 1.0, 1.0));

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

float poly2(vec3 c, float t) {
    return c.z*t*t + c.y*t +c.x;
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
    vec3 rayDir
    ) {
        float x = rayDir.x*t;
        float y = rayDir.y*t;
        float z = rayDir.z*t;

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

vec4 intersectVoxel(vec3 voxel, vec3 rayOrigin, vec3 rayDir, float tSegment) {
    ivec3 voxelInt = ivec3(voxel);
    vec3 voxelWorld = startPoint + voxel * voxelSize;

    vec3 localOrigin = (rayOrigin - voxelWorld) / voxelSize;
    vec3 localDir    = (rayDir * tSegment) / voxelSize;

    float scale = sqrt(2.0)/127.0;

    // Trilinear interpolation coefficients
    float s000 = float(getValue(voxelInt)) * scale;
    float s100 = float(getValue(voxelInt + ivec3(1,0,0))) * scale;
    float s010 = float(getValue(voxelInt + ivec3(0,1,0))) * scale;
    float s110 = float(getValue(voxelInt + ivec3(1,1,0))) * scale;
    float s001 = float(getValue(voxelInt + ivec3(0,0,1))) * scale;
    float s101 = float(getValue(voxelInt + ivec3(1,0,1))) * scale;
    float s011 = float(getValue(voxelInt + ivec3(0,1,1))) * scale;
    float s111 = float(getValue(voxelInt + ivec3(1,1,1))) * scale;

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
                if (abs(c0) < 1e-9) tIntersect = 0;
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

        float delta = 4.*c2*c2 + 12.*c3*c1;
        if (delta >= 0.) {
            float s = sqrt(delta);
            float t1 = (-c1-s)/(2.*c2);
            float t2 = (-c1+s)/(2.*c2);
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
    if (mode == 1) return computeNormal(s000, s100, s010, s110, s001, s101, s011, s111, tIntersect, rayDir);
    if (mode == 2) return vec4(voxel/float(n), 1.);
    if (mode == 3) {
        vec4 color = computeNormal(s000, s100, s010, s110, s001, s101, s011, s111, tIntersect, rayDir);
        return vec4(vec3((dot(color.xyz, lightDir)+1.)/2.), 1.0);
    }
    return vec4(vec3(tIntersect), 1.);
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

    vec3 nextVoxelBoundary = (currentVoxel + max(stepVect, vec3(0.0)))*voxelSize + startPoint;
    vec3 tMax = (nextVoxelBoundary-position)*invRay;
    vec3 tDelta = abs(invRay)*voxelSize;

    for(int i = 0; i<256; i++) {
        if(!inBoundaries(currentVoxel)) {
            break;
        }
        float tNext = min(tMax.x, min(tMax.y, tMax.z));
        vec4 color = intersectVoxel(currentVoxel, position + t*ray, ray, tNext-t);
        if (color!=vec4(0.)) {
            finalColor = color;
            return;
        }
        if(tMax.x < tMax.y) {
            if(tMax.x < tMax.z) {
                currentVoxel.x += stepVect.x;
                t = tMax.x;
                tMax.x += tDelta.x;
            }
            else {
                currentVoxel.z += stepVect.z;
                t = tMax.z;
                tMax.z += tDelta.z;
            }
        }
        else {
            if(tMax.y < tMax.z) {
                currentVoxel.y += stepVect.y;
                t = tMax.y;
                tMax.y += tDelta.y;
            }
            else {
                currentVoxel.z += stepVect.z;
                t = tMax.z;
                tMax.z += tDelta.z;
            }
        }
    }
    finalColor = vec4(0., 0., 0., 1.);
    return;
}