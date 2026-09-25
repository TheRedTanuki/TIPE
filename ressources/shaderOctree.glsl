#version 430

in vec2 fragTexCoord;
out vec4 finalColor;

uniform float ratio;
uniform vec3 cameraForward;
uniform vec3 cameraRight;
uniform vec3 cameraUp;
uniform vec3 position;
uniform float fov;

uniform int newtonNMax = 5; // precision of t determination (increase for more precision)
uniform int mode;
uniform vec3 lightDir = normalize(vec3(1.0, 1.0, 1.0));

uniform float voxelSize;
uniform int p;
uniform vec3 startPoint;

const int MAX_DEPTH = 11;

layout(std430, binding = 0) buffer octreeBuffer {
    uint data[];
};

uint getCache(uint branch) {
    return branch >> 24;
}

uint getChildAddress(uint branch) {
    return branch & 0x00FFFFFFu;
}

bool childIsLeaf(uint cache, uint child) {
    return ((cache >> child) & 1u) != 0u;
}

int leafValue(uint leaf) {
    return int(leaf & 255u) - 127;
}

float poly3(vec4 c, float t) {
    return ((c.w*t + c.z)*t + c.y)*t + c.x;
}

float poly2(vec3 c, float t) {
    return (c.z*t + c.y)*t +c.x;
}

bool signDiff(float a, float b) {
    return (a <= 0.0 && b >= 0.0) ||
           (a >= 0.0 && b <= 0.0);
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

int searchValue(ivec3 voxel, int defaultValue, int level, ivec3 nodeMin, in uint addressStack[11], in ivec3 nodeMinStack[11], int stackSize, uint address) {
    int nodeSize = 1 << level;

    // Stay in the same leaf
    if (all(greaterThanEqual(voxel, nodeMin)) &&
        all(lessThan(voxel, nodeMin + nodeSize))) {
        return defaultValue;
    }

    // Goes out of the current leaf : ascend till finding the parent
    for (int i = 0; i < MAX_DEPTH; i++) {
        if (stackSize <= 0) return 128; // Should not happen
        stackSize--;
        address = addressStack[stackSize];
        nodeMin  = nodeMinStack[stackSize];
        level++;
        nodeSize = 1 << level;
        if (all(greaterThanEqual(voxel, nodeMin)) &&
            all(lessThan(voxel, nodeMin + nodeSize))) break;
    }

    // Descend to child
    for (int i = 0; i < 24; i++) {
        uint node = data[address];
        int halfSize = nodeSize >> 1;

        ivec3 relative = voxel - nodeMin;

        uint xBit = relative.x >= halfSize ? 1u : 0u;
        uint yBit = relative.y >= halfSize ? 1u : 0u;
        uint zBit = relative.z >= halfSize ? 1u : 0u;
        uint child = xBit | (yBit << 1) | (zBit << 2);

        uint cache = getCache(node);
        uint firstChild = getChildAddress(node);
        address = firstChild + child;

        if (childIsLeaf(cache, child)) {
            return leafValue(data[address]);
        }

        if (xBit != 0u) nodeMin.x += halfSize;
        if (yBit != 0u) nodeMin.y += halfSize;
        if (zBit != 0u) nodeMin.z += halfSize;
        level--;
        nodeSize = 1 << level;
    }
    return 128;
}

vec4 intersectVoxel(vec3 local, vec3 ray, float tSegment, int defaultValue, int level, ivec3 nodeMin, vec3 boundary, float t, in uint addressStack[MAX_DEPTH], in ivec3 nodeMinStack[MAX_DEPTH], int stackSize, uint address) {
    if (level != 0) return vec4(0.);
    
    ivec3 voxelInt = ivec3(floor(local));
    int nodeSize = 1 << level;

    vec3 localOrigin = local - voxelInt;
    vec3 localDir    = (ray * tSegment)/voxelSize;

    float scale = sqrt(2.0)/127.0;

    int v000 = defaultValue;
    int v100 = searchValue(voxelInt + ivec3(1., 0., 0.), v000, level, nodeMin, addressStack, nodeMinStack, stackSize, address);
    int v010 = searchValue(voxelInt + ivec3(0., 1., 0.), v000, level, nodeMin, addressStack, nodeMinStack, stackSize, address);
    int v110 = searchValue(voxelInt + ivec3(1., 1., 0.), v000, level, nodeMin, addressStack, nodeMinStack, stackSize, address);
    int v001 = searchValue(voxelInt + ivec3(0., 0., 1.), v000, level, nodeMin, addressStack, nodeMinStack, stackSize, address);
    int v101 = searchValue(voxelInt + ivec3(1., 0., 1.), v000, level, nodeMin, addressStack, nodeMinStack, stackSize, address);
    int v011 = searchValue(voxelInt + ivec3(0., 1., 1.), v000, level, nodeMin, addressStack, nodeMinStack, stackSize, address);
    int v111 = searchValue(voxelInt + ivec3(1., 1., 1.), v000, level, nodeMin, addressStack, nodeMinStack, stackSize, address);
    if(v000 == 128 ||
    v100 == 128 ||
    v010 == 128 ||
    v110 == 128 ||
    v001 == 128 ||
    v101 == 128 ||
    v011 == 128 ||
    v111 == 128) return vec4(0., 0., 1., 1.); // debug


    float s000 = float(v000) * scale;
    float s100 = float(v100) * scale;
    float s010 = float(v010) * scale;
    float s110 = float(v110) * scale;
    float s001 = float(v001) * scale;
    float s101 = float(v101) * scale;
    float s011 = float(v011) * scale;
    float s111 = float(v111) * scale;

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
    if (mode == 1) return computeNormal(s000, s100, s010, s110, s001, s101, s011, s111, tIntersect, localOrigin, localDir, ray);
    if (mode == 2) return vec4(local/float(1 << p), 1.);
    if (mode == 3) {
        vec4 color = computeNormal(s000, s100, s010, s110, s001, s101, s011, s111, tIntersect, localOrigin, localDir, ray);
        return vec4(vec3((dot(color.xyz, lightDir)+1.)/2.), 1.0);
    }
    if (mode == 4) return vec4(
        fract(local),
        1.0
    );
    return vec4(vec3(tIntersect), 1.);
}

void main() {
    vec2 uv = fragTexCoord * 2.0 - 1.0;
    uv.x *= ratio;

    vec3 ray = normalize(cameraForward + cameraRight * uv.x * fov + cameraUp * uv.y * fov);

    int n = 1 << p;

    float worldSize = float(n-1) * voxelSize;
    vec3 endPoint = startPoint + vec3(worldSize);

    vec3 invRay = 1.0 / ray;

    vec3 t0 = (startPoint - position) * invRay;

    vec3 t1 = (endPoint - position) * invRay;

    vec3 tmin3 = min(t0, t1);
    vec3 tmax3 = max(t0, t1);

    float tmin = max(max(tmin3.x, tmin3.y), tmin3.z);

    float tmax = min(min(tmax3.x, tmax3.y), tmax3.z);

    if (tmax < 0. || tmin > tmax) {
        finalColor = vec4(0., 0., 0., 1.);
        return;
    }

    float t = max(tmin, 0.0);


    float rayEpsilon = max(voxelSize * 1e-5, 1e-6);

    if (tmin > 0.0) t += rayEpsilon;

    vec3 local;

    // Search state variables
    int level = p;
    uint address = 0u;
    ivec3 nodeMin = ivec3(0);
    bool isLeaf = false;

    // Stack
    uint addressStack[MAX_DEPTH];
    ivec3 nodeMinStack[MAX_DEPTH];
    int stackSize = 0;
    finalColor = vec4(1., 0., 0., 1.);
    for (int iteration = 0; iteration < 512; iteration++) {
        // recompute local to avoid additionnal floating point errors
        local = (position + ray * t - startPoint)/ voxelSize;

        if (any(lessThan(local, vec3(0.0))) || any(greaterThanEqual(local, vec3(float(n-1))))) {
            return;
        }

        uint node = data[address];

        if (isLeaf) {
            int nodeSize = 1 << level;
            vec3 boundary;

            if (ray.x > 0.) boundary.x = float(nodeMin.x + nodeSize);
            else            boundary.x = float(nodeMin.x);

            if (ray.y > 0.) boundary.y = float(nodeMin.y + nodeSize);
            else            boundary.y = float(nodeMin.y);

            if (ray.z > 0.) boundary.z = float(nodeMin.z + nodeSize);
            else            boundary.z = float(nodeMin.z);

            int v000 = leafValue(node);

            const float INF = 1e30;
            vec3 tExit;

            if (abs(ray.x) > 1e-8)  tExit.x = t + (boundary.x - local.x)*voxelSize/ray.x;
            else                    tExit.x = INF;

            if (abs(ray.y) > 1e-8)  tExit.y = t + (boundary.y - local.y)*voxelSize/ray.y;
            else                    tExit.y = INF;

            if (abs(ray.z) > 1e-8)  tExit.z = t + (boundary.z - local.z)*voxelSize/ray.z;
            else                    tExit.z = INF;

            float nextT = min(tExit.x, min(tExit.y, tExit.z));
            vec4 color = intersectVoxel(local, ray, nextT-t, v000, level, nodeMin, boundary, t, addressStack, nodeMinStack, stackSize, address);
            if (color!=vec4(0.)) {
                finalColor = color;
                return;
            }

            if (nextT <= t) nextT = t + rayEpsilon;
            t = nextT;

            // reascend
            if (stackSize <= 0) {
                finalColor = vec4(0., 0., 0., 1.);
                return;
            }

            stackSize--;

            address = addressStack[stackSize];
            nodeMin = nodeMinStack[stackSize];

            level++;
            isLeaf = false;

            continue;
        }

        // Internal Node

        int nodeSize = 1 << level;
        int halfSize = nodeSize >> 1;
        ivec3 nodeMax = nodeMin + ivec3(nodeSize);


        if (any(lessThan(local, vec3(nodeMin))) || any(greaterThanEqual(local, vec3(nodeMax)))) {
            // the ray exited the node
            // reascend
            if (stackSize <= 0) {
                finalColor = vec4(0., 0., 0., 1.);
                return;
            }

            stackSize--;

            address = addressStack[stackSize];

            nodeMin = nodeMinStack[stackSize];

            level++;
            isLeaf = false;

            continue;
        }

        ivec3 voxel = ivec3(floor(local));

        ivec3 relative = voxel - nodeMin;

        uint xBit = relative.x >= halfSize ? 1u : 0u;
        uint yBit = relative.y >= halfSize ? 1u : 0u;
        uint zBit = relative.z >= halfSize ? 1u : 0u;

        uint child = xBit | (yBit << 1) | (zBit << 2);

        uint cache = getCache(node);
        uint firstChild = getChildAddress(node);

        // stack the parent node
        if (stackSize >= MAX_DEPTH)
        {
            finalColor =
                vec4(0., 0., 0., 1.);
            return;
        }

        addressStack[stackSize] = address;
        nodeMinStack[stackSize] = nodeMin;

        stackSize++;

        ivec3 childMin = nodeMin;

        if (xBit != 0u) childMin.x += halfSize;
        if (yBit != 0u) childMin.y += halfSize;
        if (zBit != 0u) childMin.z += halfSize;

        // descend
        address = firstChild + child;
        nodeMin = childMin;

        level--;

        isLeaf = childIsLeaf(cache, child);
    }
    finalColor = vec4(0., 1., 0., 1.);
}