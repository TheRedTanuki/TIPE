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

layout(std430, binding = 0) buffer octreeBuffer
{
    uint data[];
};

uint getCache(uint branch)
{
    return branch >> 24;
}

uint getChildAddress(uint branch)
{
    return branch & ((1u<<24)-1u);
}

bool childIsLeaf(uint cache, uint child)
{
    return ((cache >> child) & 1u) != 0u;
}

int leafValue(uint leaf)
{
    return int(leaf & 255u) - 127;
}

void pushStack(out uint stack[11], out int iStack, uint nodeAdress) {
    stack[iStack] = nodeAdress;
    iStack++;
}

uint popStack(out uint stack[11], out int iStack) {
    iStack--;
    return stack[iStack];
}

void main()
{
    vec2 uv = fragTexCoord * 2.0 - 1.0;
    uv.x *= ratio;

    uint stack[11];
    int iStack = 0;

    vec3 ray = normalize(
        cameraForward +
        cameraRight * uv.x * fov +
        cameraUp * uv.y * fov
    );

    int resolution = 1 << (p + 1);
    float worldSize = float(resolution) * voxelSize;

    vec3 worldMin = startPoint;
    vec3 worldMax = startPoint + vec3(worldSize);

    vec3 invRay = 1.0 / ray;

    vec3 t0 = (worldMin - position) * invRay;
    vec3 t1 = (worldMax - position) * invRay;

    vec3 tMin3 = min(t0, t1);
    vec3 tMax3 = max(t0, t1);

    float tNear = max(max(tMin3.x, tMin3.y), tMin3.z);
    float tFar  = min(min(tMax3.x, tMax3.y), tMax3.z);

    if(tFar < 0.0 || tNear > tFar)
    {
        finalColor = vec4(0.0,0.0,0.0,1.0);
        return;
    }

    float t = max(tNear, 0.0);
    vec3 pos = position + ray * t;

    vec3 local = (pos - startPoint) / voxelSize;

    ivec3 voxel;
    ivec3 voxelNode;
    int level = p;
    
    bool isLeaf = false;
    uint address = 0;

    vec3 stepVect = sign(ray);

    while(t < tFar) {
        uint node = data[address];
        voxel = ivec3(floor(local+ray*1e-4));
        voxelNode = voxel/ivec3(1<<level);
        if(isLeaf) {
            int value = leafValue(node);
            if (value!=-127 && value!=127) {
                finalColor = vec4(1.);
                return;
            }
            vec3 nextVoxelBoundary = vec3(voxelNode) + max(stepVect*(1<<level), vec3(0.));
            vec3 tMax = nextVoxelBoundary-local;
            vec3 tDelta = abs(invRay);
            float tMin = min(tMax.x, min(tMax.y, tMax.z));
            local += ray*tMin;

            level++;
            address = popStack(stack, iStack);
        }
        else {
            if(all(greaterThanEqual(local, vec3(voxelNode))) && all(lessThanEqual(local, vec3(voxelNode)+vec3(1.*(1<<level))))) { // check if we are in the voxel
                uint cache = getCache(node);
                uint firstChild = getChildAddress(node);

                uint xBit = local.x - float(voxel.x) < 0.5*(1<<level) ? 0 : 1; // 0.5*(1<<level) = 1<<(level-1)
                uint yBit = local.y - float(voxel.y) < 0.5*(1<<level) ? 0 : 1;
                uint zBit = local.z - float(voxel.z) < 0.5*(1<<level) ? 0 : 1;

                uint child =
                    xBit +
                    (yBit << 1) +
                    (zBit << 2);

                pushStack(stack, iStack, address);
                address = firstChild + child;
            }
            else { // if not -> go to father
                if(level>p) {
                    finalColor = vec4(1., 0., 0., 1.);
                    return;
                }
                else {
                    level++;
                    address = popStack(stack, iStack);
                }

            }
        }      
        
    }

    finalColor = vec4(0.0,0.0,0.0,1.0);
}