#define GRAPHICS_API_OPENGL_43
#include <raylib.h>
#include <assert.h>
#include <stdlib.h>
#include <stdio.h>
#include <stdbool.h>
#include <math.h>
#include <stdint.h>
#include <rlgl.h>
#include <raymath.h>

// gcc mainOctree.c -O3 -o mainOctree -lraylib -lm -lpthread -ldl -lrt -lX11 && ./mainOctree

typedef struct Node{
    uint8_t cache;
	uint8_t data;
	bool isLeaf;
	struct Node* children[8];
} Node;

int intClamp(int x, int m, int M) {
	if(x>M) return M;
	if(x<m) return m;
	return x;
}

// Quaternion functions

Quaternion inverse(Quaternion q) {
	return (Quaternion){q.x, -q.y, -q.z, -q.w};
}

Quaternion rotateQuat(Quaternion p, Quaternion q) {
	return QuaternionMultiply(q, QuaternionMultiply(p, inverse(q)));
}

Quaternion rotationQuat(Quaternion axis, double angle) {
	double c = cos(angle/2);
	double s = sin(angle/2);
	return (Quaternion){c, s*axis.y, s*axis.z, s*axis.w};
}

Vector3 quatToVect3(Quaternion q) {
	return (Vector3){q.y, q.z, q.w};
}

double sdf(Vector3 pos, Vector2 t) {
  Vector2 q = (Vector2){Vector2Length((Vector2){pos.x, pos.z})-t.x, pos.y};
  return Vector2Length(q)-t.y;
}

int quickExp(int n, int p) {
    if(p==0) return 1;
    if(p%2==0) {
        int temp = quickExp(n, p/2);
        return temp*temp;
    }
    return n*quickExp(n, p-1);
}

uint8_t computeNode(int n, int x, int y, int z) {
    double c = (n-1)/2.;
    Vector3 pos = (Vector3){(double)x-c, (double)y-c, (double)z-c};
    double dist = sdf(pos, (Vector2){6., 3.})/(sqrt(2))*127;
    uint8_t val = (uint8_t)(intClamp((int)dist, -127, 127)+127);
	return val;
}

bool nodeEquality(Node* node1, Node* node2) {
	return node1->isLeaf	== node2->isLeaf
		&& node1->cache		== node2->cache
		&& node1->data		== node2->data;
}

Node* createOctree(int p, int n, int x, int y, int z) {
	if(p==0) {
		Node* node = malloc(sizeof(Node));
		for(int i = 0; i<8; i++) {
			node->children[i] = NULL;
		}
		node->isLeaf = true;
		node->cache=0;
		node->data=computeNode(n, x, y, z);
		return node;
	}
	else {
		int offset = 1<<p;
		Node* node000 = createOctree(p-1, n, x, y, z);
		Node* node100 = createOctree(p-1, n, x+offset, y, z);
		Node* node010 = createOctree(p-1, n, x, y+offset, z);
		Node* node110 = createOctree(p-1, n, x+offset, y+offset, z);
		Node* node001 = createOctree(p-1, n, x, y, z+offset);
		Node* node101 = createOctree(p-1, n, x+offset, y, z+offset);
		Node* node011 = createOctree(p-1, n, x, y+offset, z+offset);
		Node* node111 = createOctree(p-1, n, x+offset, y+offset, z+offset);
		if (node000->isLeaf
		&& nodeEquality(node000, node100)
		&& nodeEquality(node000, node010)
		&& nodeEquality(node000, node110)
		&& nodeEquality(node000, node001)
		&& nodeEquality(node000, node101)
		&& nodeEquality(node000, node011)
		&& nodeEquality(node000, node111)
		) {
			Node* node = node000;
			free(node100);
			free(node010);
			free(node110);
			free(node001);
			free(node101);
			free(node011);
			free(node111);
			return node;
		}
		else {
			Node* node = malloc(sizeof(Node));
			node->children[0] = node000;
			node->children[1] = node100;
			node->children[2] = node010;
			node->children[3] = node110;
			node->children[4] = node001;
			node->children[5] = node101;
			node->children[6] = node011;
			node->children[7] = node111;
			node->data=0;
			node->isLeaf=false;
			uint8_t cache = (node000->isLeaf ? 0x1 : 0x0)
				| (node100->isLeaf ? 0x1 : 0x0)<<1
				| (node010->isLeaf ? 0x1 : 0x0)<<2
				| (node110->isLeaf ? 0x1 : 0x0)<<3
				| (node001->isLeaf ? 0x1 : 0x0)<<4
				| (node101->isLeaf ? 0x1 : 0x0)<<5
				| (node011->isLeaf ? 0x1 : 0x0)<<6
				| (node111->isLeaf ? 0x1 : 0x0)<<7;
			return node;
		}
	}
}

void freeNode(Node* node) {
    if(!node->isLeaf) {
        for(int i = 0; i < 8; i++) {
            freeNode(node->children[i]);
        }
    }
    free(node);
}

int count(Node* node) {
	if(node->isLeaf) return 1;
	int sum = 0;
	for(int i = 0; i<8; i++) {
		sum += count(node->children[i]);
	}
	return sum;
}

void updateBuffer(uint32_t* octreeBuffer, int p, int n) {
}

int main ()
{
	SetConfigFlags(FLAG_WINDOW_HIGHDPI);
	InitWindow(1280, 800, "Test");
	
	ToggleFullscreen();
	float ratio = (float)GetScreenWidth()/GetScreenHeight();

	Shader shader = LoadShader(0, "ressources/shaderOctree.glsl");
	RenderTexture2D target = LoadRenderTexture(GetScreenWidth(), GetScreenHeight());

	// Uniform locations
	int ratioLoc = GetShaderLocation(shader, "ratio");
	int cameraForwardLoc = GetShaderLocation(shader, "cameraForward");
	int cameraRightLoc = GetShaderLocation(shader, "cameraRight");
	int cameraUpLoc = GetShaderLocation(shader, "cameraUp");
	int positionLoc = GetShaderLocation(shader, "position");
	int nLoc = GetShaderLocation(shader, "n");
	int startPointLoc = GetShaderLocation(shader, "startPoint");
	int voxelSizeLoc = GetShaderLocation(shader, "voxelSize");
	int fovLoc = GetShaderLocation(shader, "fov");
	int modeLoc = GetShaderLocation(shader, "mode");

	float fov = 1.2;
	Vector3 startPoint = (Vector3){0., 0., 0.};
	float voxelSize = 1.;

    int p = 5;
	int n = 1<<p;
    int32_t* octreeBuffer = malloc(quickExp(8, p)*sizeof(int32_t));
	Node* octree = createOctree(p, n, 0, 0, 0);
	printf("%d\n", count(octree));
	free(octreeBuffer);
	freeNode(octree);
	
	bool updateEnabled = false;
	int mode = 0;
	int modeNumber = 4;

	SetShaderValue(shader, nLoc, &n, SHADER_UNIFORM_INT);
	SetShaderValue(shader, fovLoc, &fov, SHADER_UNIFORM_FLOAT);
	SetShaderValue(shader, startPointLoc, &startPoint, SHADER_UNIFORM_VEC3);
	SetShaderValue(shader, voxelSizeLoc, &voxelSize, SHADER_UNIFORM_FLOAT);

	Vector3 pos = {-1., -1., -1.};
	Quaternion forward = {0., 1., 0., 0.};
	Quaternion right = {0., 0., 1., 0.};
	Quaternion up = {0., 0., 0., 1.};
	
	DisableCursor();

	double pitch = 0.0;
	double yaw = 0.0;
	double roll = 0.0;
	SetTargetFPS(1000);

	while (!WindowShouldClose())
	{
		if (updateEnabled) {
		}
		Vector2 delta = GetMouseDelta();
		pitch -= (double)delta.y*GetFrameTime()*0.5;
		yaw -= (double)delta.x*GetFrameTime()*0.5;
		//roll += 0.02*((IsKeyDown(KEY_Q) ? 1 : 0) + (IsKeyDown(KEY_E) ? -1 : 0));

		Quaternion rQuat = QuaternionMultiply(rotationQuat((Quaternion){0., 0., 0., 1.}, yaw), QuaternionMultiply(rotationQuat((Quaternion){0., 0., 1., 0.}, pitch), rotationQuat((Quaternion){0., 1., 0., 0.}, roll)));
		forward = rotateQuat((Quaternion){0., 1., 0., 0.}, rQuat);
		right = rotateQuat((Quaternion){0., 0., 1., 0.}, rQuat);
		up = rotateQuat((Quaternion){0., 0., 0., 1.}, rQuat);
		Vector3 vectForward = quatToVect3(forward);
		Vector3 vectRight = quatToVect3(right);
		Vector3 vectUp = quatToVect3(up);

		if(IsKeyDown(KEY_W)) pos = Vector3Add(Vector3Scale(vectForward, GetFrameTime()*25), pos);
		if(IsKeyDown(KEY_S)) pos = Vector3Add(Vector3Scale(vectForward, -GetFrameTime()*25), pos);
		if(IsKeyDown(KEY_A)) pos = Vector3Add(Vector3Scale(vectRight, -GetFrameTime()*25), pos);
		if(IsKeyDown(KEY_D)) pos = Vector3Add(Vector3Scale(vectRight, GetFrameTime()*25), pos);
		if(IsKeyDown(KEY_SPACE)) pos = Vector3Add(Vector3Scale(vectUp, GetFrameTime()*10), pos);
		if(IsKeyDown(KEY_LEFT_SHIFT)) pos = Vector3Add(Vector3Scale(vectUp, -GetFrameTime()*10), pos);
		if(IsKeyPressed(KEY_Q)) updateEnabled ^= true;
		if(IsKeyPressed(KEY_E)) mode = (mode+1)%modeNumber;
		
		SetShaderValue(shader, ratioLoc, &ratio, SHADER_UNIFORM_FLOAT);
		SetShaderValue(shader, cameraForwardLoc, &vectForward, SHADER_UNIFORM_VEC3);
		SetShaderValue(shader, cameraRightLoc, &vectRight, SHADER_UNIFORM_VEC3);
		SetShaderValue(shader, cameraUpLoc, &vectUp, SHADER_UNIFORM_VEC3);
		SetShaderValue(shader, positionLoc, &pos, SHADER_UNIFORM_VEC3);
		SetShaderValue(shader, modeLoc, &mode, SHADER_UNIFORM_INT);

		BeginTextureMode(target);
			DrawRectangle(0, 0, GetScreenWidth(), GetScreenHeight(), RAYWHITE);
		EndTextureMode();

		BeginDrawing();

			ClearBackground(RAYWHITE);
			BeginShaderMode(shader);
				DrawTextureRec(target.texture, (Rectangle){ 0, 0, (float)target.texture.width, (float)-target.texture.height}, (Vector2){0,0}, RAYWHITE);
			EndShaderMode();
			DrawFPS(0, 0);
		EndDrawing();
	}

	UnloadShader(shader);
	CloseWindow();
	return 0;
}