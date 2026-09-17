#version 430

in vec2 fragTexCoord;
out vec4 finalColor;

uniform float ratio;
uniform vec3 cameraForward;
uniform vec3 cameraRight;
uniform vec3 cameraUp;
uniform vec3 position;
uniform float fov;

uniform float voxelSize;
uniform int p;
uniform vec3 startPoint;

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

int searchValue(vec3 local, int defaultValue, int level, ivec3 nodeMin, vec3 ray, int nodeSize, vec3 boundary, float t, in uint addressStack[11], in ivec3 nodeMinStack[11], int stackSize, uint address) {
    const float INF = 1e30;

    vec3 tExit;

    if (abs(ray.x) > 1e-8)  tExit.x = t + (boundary.x - local.x)*voxelSize/ray.x;
    else                    tExit.x = INF;

    if (abs(ray.y) > 1e-8)  tExit.y = t + (boundary.y - local.y)*voxelSize/ray.y;
    else                    tExit.y = INF;

    if (abs(ray.z) > 1e-8)  tExit.z = t + (boundary.z - local.z)*voxelSize/ray.z;
    else                    tExit.z = INF;

    float nextT = min(tExit.x, min(tExit.y, tExit.z));
    // if we stay in the same cube : the v000 value is used
    if (nextT - t < 0.) return defaultValue;

    bool isLeaf = false;

    // search in the tree
    for (int iteration = 0; iteration < 24; iteration++) {

        uint node = data[address];

        if (isLeaf) {
            return leafValue(node);
        }

        // Internal Node

        int nodeSize = 1 << level;

        int halfSize = nodeSize >> 1;

        ivec3 nodeMax = nodeMin + ivec3(nodeSize);


        if (any(lessThan(local, vec3(nodeMin))) || any(greaterThanEqual(local, vec3(nodeMax)))) {
            // the ray exited the node
            // reascend
            if (stackSize <= 0) {
                return -127; // this case is extreme and should not be possible - debug
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
        if (stackSize >= 11)
        {
            return -127; // this case should neither be possible - debug
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
    
    return -127;
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
    uint addressStack[11];
    ivec3 nodeMinStack[11];
    int stackSize = 0;
    finalColor = vec4(0., 0., 0., 1.);
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

            if (ray.x > 0.)
                boundary.x = float(nodeMin.x + nodeSize);
            else
                boundary.x = float(nodeMin.x);

            if (ray.y > 0.)
                boundary.y = float(nodeMin.y + nodeSize);
            else
                boundary.y = float(nodeMin.y);

            if (ray.z > 0.)
                boundary.z = float(nodeMin.z + nodeSize);
            else
                boundary.z = float(nodeMin.z);

            int v000 = leafValue(node);

            // get the 7 other blocks :
            vec3 stepVect = sign(ray);
            int v100 = searchValue(local + vec3(1., 0., 0.), v000, level, nodeMin, ray, nodeSize, boundary, t, addressStack, nodeMinStack, stackSize, address);
            int v010 = searchValue(local + vec3(0., 1., 0.), v000, level, nodeMin, ray, nodeSize, boundary, t, addressStack, nodeMinStack, stackSize, address);
            int v001 = searchValue(local + vec3(0., 0., 1.), v000, level, nodeMin, ray, nodeSize, boundary, t, addressStack, nodeMinStack, stackSize, address);
            int v110 = searchValue(local + vec3(1., 1., 0.), v000, level, nodeMin, ray, nodeSize, boundary, t, addressStack, nodeMinStack, stackSize, address);
            int v011 = searchValue(local + vec3(0., 1., 1.), v000, level, nodeMin, ray, nodeSize, boundary, t, addressStack, nodeMinStack, stackSize, address);
            int v101 = searchValue(local + vec3(1., 0., 1.), v000, level, nodeMin, ray, nodeSize, boundary, t, addressStack, nodeMinStack, stackSize, address);
            int v111 = searchValue(local + vec3(1., 1., 1.), v000, level, nodeMin, ray, nodeSize, boundary, t, addressStack, nodeMinStack, stackSize, address);

            // debug
            if (v000 != -127 && v000 != 127) {
                //float v = float(v000 + 127) / 254.;
                finalColor = vec4(v000+v100, v010+v110, v001+v101, 1.);
                return;
            }

            const float INF = 1e30;

            vec3 tExit;

            if (abs(ray.x) > 1e-8)  tExit.x = t + (boundary.x - local.x)*voxelSize/ray.x;
            else                    tExit.x = INF;

            if (abs(ray.y) > 1e-8)  tExit.y = t + (boundary.y - local.y)*voxelSize/ray.y;
            else                    tExit.y = INF;

            if (abs(ray.z) > 1e-8)  tExit.z = t + (boundary.z - local.z)*voxelSize/ray.z;
            else                    tExit.z = INF;

            float nextT = min(tExit.x, min(tExit.y, tExit.z));

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
        if (stackSize >= 11)
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
}