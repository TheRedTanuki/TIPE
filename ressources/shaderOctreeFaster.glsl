#version 430
#extension GL_ARB_gpu_shader_int64 : enable

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
uniform int p = 5;
int n = 1<<p;
int max_depth = p+1;
uniform vec3 startPoint;

const int MAX_DEPTH = 11;
const float scale = sqrt(3.)/127.;

layout(std430, binding = 0) buffer octreeBuffer {
    uint64_t data[];
};

uint getCache(uint64_t branch) {
    return uint(branch) >> 24;
}

uint getChildAddress(uint64_t branch) {
    return uint(branch) & 0x00FFFFFFu;
}

bool childIsLeaf(uint cache, uint child) {
    return ((cache >> child) & 1u) != 0u;
}

int leafValue(uint64_t leaf, int offset) {
    return int((leaf>>(8*offset)) & (255u)) - 127;
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

// Partly based on https://momentsingraphics.de/CubicRoots.html
bool minCubicRootBetweenZeroAndOne(vec4 Coefficient, out float t)
{
    // Degerenated cases
    if (abs(Coefficient.w) < 1e-6) {
        if (abs(Coefficient.z) < 1e-6) {
            if (abs(Coefficient.y) < 1e-6) {
                if (abs(Coefficient.x) < 1e-6) {
                    t = Coefficient.x;
                    return true;
                }
                else return false;
            }
            float t0 = -Coefficient.x / Coefficient.y;
            if (t0 >= 0. && t0 <= 1.) {
                t = t0;
                return true;
            }
            else return false;
        }
        else {
            float d = Coefficient.y*Coefficient.y - 4.*Coefficient.z*Coefficient.x;
            if (d < 0.) return false;

            float t1 = (-Coefficient.y - sqrt(d))/(2.*Coefficient.z);
            if (t1 >= 0. && t1 <= 1.) {
                t = t1;
                return true;
            }
            else {
                float t2 = (-Coefficient.y + sqrt(d))/(2.*Coefficient.z);
                if (t2 >= 0. && t2 <= 1.) {
                    t = t2;
                    return true;
                }
                else return false;
            }
        }
    }
    else {
        // Normal cases
        // Normalize the polynomial
        Coefficient.xyz /= Coefficient.w;
        // Divide middle coefficients by three
        Coefficient.yz /= 3.0;

        // Hessian coefficients and discriminant
        vec3 Delta = vec3(
            -Coefficient.z * Coefficient.z + Coefficient.y,
            -Coefficient.y * Coefficient.z + Coefficient.x,
            dot(vec2(Coefficient.z, -Coefficient.y), Coefficient.xy)
        );
        float Discriminant = dot(vec2(4.0 * Delta.x, -Delta.y), Delta.zy);

        // Depressed cubic: x^3 + 3*Depressed.y*x + Depressed.x = 0
        vec2 Depressed = vec2(
            -2.0 * Coefficient.z * Delta.x + Delta.y,
            Delta.x
        );

        bool allRealRoots = (Discriminant >= 0.0);

        if (allRealRoots)
        {
            // Three real roots: trigonometric solution
            float Theta = atan(sqrt(Discriminant), -Depressed.x) / 3.0;
            vec2 CubicRoot = vec2(cos(Theta), sin(Theta));
            vec3 Root = vec3(
                CubicRoot.x,
                dot(vec2(-0.5, -0.5 * sqrt(3.0)), CubicRoot),
                dot(vec2(-0.5,  0.5 * sqrt(3.0)), CubicRoot)
            );
            vec3 t123 = (2.0 * sqrt(max(-Depressed.y, 0.0)) * Root - Coefficient.z).yzx; // First root is y, then z, then x, so we arrange them in order
            if(t123.x >= 0. && t123.x <= 1.) {
                t = t123.x;
                return true;
            }
            else if(t123.y >= 0. && t123.y <= 1.) {
                t = t123.y;
                return true;
            }
            else if(t123.z >= 0. && t123.z <= 1.) {
                t = t123.z;
                return true;
            }
            else return false;
        }
        else
        {
            // One real root: Cardano. q^2/4 + p^3 == -Discriminant/4
            float s = 0.5 * sqrt(-Discriminant);
            // Pick the cube-root term with the larger magnitude to avoid cancellation
            float w = -0.5 * Depressed.x - (Depressed.x >= 0.0 ? s : -s);
            float u = sign(w) * pow(abs(w), 1.0 / 3.0);;
            // u * v = -p, so the second term is -p / u
            float v = (u != 0.0) ? -Depressed.y / u : 0.0;
            float x = u + v - Coefficient.z;   // undo the depression
            if(x >= 0. && x <= 1.) {
                t = x;
                return true;
            }
            else return false;
        }
    }
    return false;
}

vec4 intersectVoxel(uint64_t node, vec3 local, vec3 ray, float tSegment, int defaultValue, int level, ivec3 nodeMin, vec3 boundary, float t, in uint addressStack[MAX_DEPTH], int stackSize, uint address) {
    if (level != 0) return vec4(0.);
    
    ivec3 voxelInt = ivec3(floor(local));
    int nodeSize = 1 << level;

    vec3 localOrigin = local - voxelInt;
    vec3 localDir    = (ray * tSegment)/voxelSize;

    int v000 = defaultValue;
    int v100 = leafValue(node, 1);
    int v010 = leafValue(node, 2);
    int v110 = leafValue(node, 3);
    int v001 = leafValue(node, 4);
    int v101 = leafValue(node, 5);
    int v011 = leafValue(node, 6);
    int v111 = leafValue(node, 7);

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

    float tIntersect;
    if(!minCubicRootBetweenZeroAndOne(c, tIntersect)) return vec4(0.);

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

    float worldSize = float(n) * voxelSize;
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
    int stackSize = 0;
    finalColor = vec4(1., 0., 0., 1.);
    for (int iteration = 0; iteration < 2*max_depth*3*n-1; iteration++) {
        // recompute local to avoid additionnal floating point errors
        local = (position + ray * t - startPoint)/ voxelSize;

        if (any(lessThan(local, vec3(0.0))) || any(greaterThanEqual(local, vec3(float(n))))) {
            finalColor = vec4(vec3(0.), 1.);
            return;
        }

        uint64_t node = data[address];

        if (isLeaf) {
            int nodeSize = 1 << level;
            vec3 boundary;

            if (ray.x > 0.) boundary.x = float(nodeMin.x + nodeSize);
            else            boundary.x = float(nodeMin.x);

            if (ray.y > 0.) boundary.y = float(nodeMin.y + nodeSize);
            else            boundary.y = float(nodeMin.y);

            if (ray.z > 0.) boundary.z = float(nodeMin.z + nodeSize);
            else            boundary.z = float(nodeMin.z);

            int v000 = leafValue(node, 0);

            const float INF = 1e30;
            vec3 tExit;

            if (abs(ray.x) > 1e-8)  tExit.x = t + (boundary.x - local.x)*voxelSize/ray.x;
            else                    tExit.x = INF;

            if (abs(ray.y) > 1e-8)  tExit.y = t + (boundary.y - local.y)*voxelSize/ray.y;
            else                    tExit.y = INF;

            if (abs(ray.z) > 1e-8)  tExit.z = t + (boundary.z - local.z)*voxelSize/ray.z;
            else                    tExit.z = INF;

            float nextT = min(tExit.x, min(tExit.y, tExit.z));
            vec4 color = intersectVoxel(node, local, ray, nextT-t, v000, level, nodeMin, boundary, t, addressStack, stackSize, address);
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
            level++;
            nodeMin &= ivec3(~((1 << level) - 1));

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
            level++;
            nodeMin &= ivec3(~((1 << level) - 1));

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