#version 330

in vec2 fragTexCoord;
out vec4 finalColor;

uniform float ratio;
uniform vec3 cameraForward = vec3 (1.0, 0.0, 0.0);
uniform vec3 cameraRight = vec3 (0.0, 1.0, 0.0);
uniform vec3 cameraUp = vec3 (0.0, 0.0, 1.0);
uniform vec3 position = vec3 (0.0, 0.0, -2.0);
uniform sampler2D voxelArray;
uniform int n;


bool getVoxel(ivec3 p) {
    int x = p.x;
    int y = p.y + p.z * n;
    vec2 uv;
    uv.x = (float(x) + 0.5) / float(n);
    uv.y = (float(y) + 0.5) / float(n * n);
    return texture(voxelArray, uv).r > 0.5;
}

void main()
{
    vec2 uv = fragTexCoord;
    
    uv *= 2.0;
    uv -= 1.0;
    uv.x *= ratio;

    vec3 ray = normalize(cameraForward + uv.x*cameraRight + uv.y*cameraUp);

    vec3 invRay = 1.0 / ray;

    vec3 t0 = (-position) * invRay;
    vec3 t1 = (vec3(float(n)) - position) * invRay;

    vec3 tmin3 = min(t0, t1);
    vec3 tmax3 = max(t0, t1);

    float tmin = max(max(tmin3.x, tmin3.y), tmin3.z);
    float tmax = min(min(tmax3.x, tmax3.y), tmax3.z);

    if(tmax < 0.0 || tmin > tmax){
        finalColor = vec4(1.0, 0.0, 0.0, 1.0);
        return;
    }

    finalColor = vec4(1.0, 1.0, 1.0, 1.0);
    return;
}