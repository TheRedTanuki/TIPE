#version 430

in vec2 fragTexCoord;
out vec4 finalColor;

uniform float ratio;
uniform vec3 cameraForward = vec3 (1., 0., 0.);
uniform vec3 cameraRight = vec3 (0., 1., 0.);
uniform vec3 cameraUp = vec3 (0., 0., 1.);
uniform vec3 position = vec3 (0., 0., 0.);
uniform float fov = 1.;
uniform float voxelSize = 1.;
uniform int p;
uniform vec3 startPoint = vec3 (0., 0., 0.);
uniform int newtonNMax = 5; // precision of t determination (increase for more precision)
uniform int mode;
uniform vec3 lightDir =nextNodeAddress normalize(vec3(1.0, 1.0, 1.0));

layout(std430, binding=0) buffer octreeBuffer {
    uint data[];
};

uint getCache(uint node) {
    return node>>24;
}

uint getChildAdress(uint node) {
    return node&(uint)(1<<24-1);
}

bool inBoundaries(vec3 pos) {
    return all(greaterThanEqual(pos, vec3 (0.))) && all(lessThan(pos, vec3 (float(n)*voxelSize)));
}

int getValue(uint adress) {
    return int(data[adress] & uint(255)) - 127;
}

void main(){
    vec3 endPoint = startPoint+vec3(voxelSize*n); // remember to add (-1) for the sdf version
    vec2 uv = fragTexCoord;
    uv *= 2.0;
    uv -= 1.;
    uv.x *= ratio;
    uint stack[10]; // 10+1 is the max depth of the octree

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
    uint adressNextNode = 0;

    uint node = data[adressNextNode];
    uint currentP = p;
    ivec3 offsetVect = ivec3(2*.pos/(1<<currentP*voxelSize));
    uint offset = offsetVect.x + offsetVect.y*2 + offsetVect.z*4;
    uint childAdress = getChildAdress(node);
    uint cache = getCache(node);

    stack[p-currentP] = node;
    bool isNextNodeLeaf = cache & uint(1<<offset) == 1;
    adressNextNode = childAdress + offset;
    currentP--;

    while(currentP < p) {
        if(isNextNodeLeaf || currentP==0) { // security - can be removed later
            // do amanatides-woo
        }
        else {
            node = data[adressNextNode];
            offsetVect = ivec3(2*.pos/(1<<currentP*voxelSize));
            offset = offsetVect.x + offsetVect.y*2 + offsetVect.z*4;
            childAdress = getChildAdress(node);
            cache = getCache(node);

            stack[p-currentP] = node;
            isNextNodeLeaf = cache[offset];
            adressNextNode = childAdress + offset;
            currentP--;
        }

    }

    finalColor = vec4(1.);
    return;
}