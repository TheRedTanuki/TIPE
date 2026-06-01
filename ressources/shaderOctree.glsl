#version 430

in vec2 fragTexCoord
out vec4 finalColor

layout(std430, binding=0) buffer octreeBuffer {
    uint data[];
}
void main(){
    finalColor = vec4(1.);
    return;
}