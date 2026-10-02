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

// gcc mainOctreeFaster.c -O3 -o mainOctreeFaster -lraylib -lm -lpthread -ldl -lrt -lX11 && ./mainOctreeFaster

#define scale 127./sqrt(3)

typedef struct Node{
    uint8_t cache;
	uint8_t data000;
    uint8_t data100;
    uint8_t data010;
    uint8_t data110;
    uint8_t data001;
    uint8_t data101;
    uint8_t data011;
    uint8_t data111;
	bool isLeaf;
	struct Node* children[8];
} Node;

typedef struct NodeStack{
	Node** array;
	int capacity;
	int size;
} NodeStack;

typedef struct NodeQueue{
	Node** array;
	int capacity;
	int start;
	int size;
} NodeQueue;

int intClamp(int x, int m, int M) {
	if(x>M) return M;
	if(x<m) return m;
	return x;
}

// n modulo p (returning the true positive modulo if n is negative)
int modulo(int n, int p) {
	int res = n%p;
	if(res>=0) return res;
	return res+p;
}

double boxSDF(Vector3 p, Vector3 b, double r) {
	Vector3 q = Vector3Add(Vector3Subtract((Vector3){fabs(p.x), fabs(p.y), fabs(p.z)}, b), (Vector3){r, r, r});
	return Vector3Length(Vector3Max(q, (Vector3){0., 0., 0.})) + fmin(fmax(q.x, fmax(q.y, q.z)), 0.) - r;
}

double torusSDF(Vector3 pos, Vector2 t) {
  Vector2 q = (Vector2){Vector2Length((Vector2){pos.x, pos.z})-t.x, pos.y};
  return Vector2Length(q)-t.y;
}

double roundedBarSDF(Vector3 pos, Vector3 start, Vector3 end, double r) {
	Vector3 pa = Vector3Subtract(pos, start);
	Vector3 ba = Vector3Subtract(end, start);
	float h = Clamp( Vector3DotProduct(pa,ba)/Vector3DotProduct(ba,ba), 0., 1.);
	return Vector3Length(Vector3Subtract(pa, Vector3Scale(ba, h))) - r;
}

double sphereSDF(Vector3 p, double r) {
	return Vector3Length(p) - r;
}

double smoothUnionSDF(double a, double b, double k) {
	k *= 4.;
	double h = fmax(k - fabs(a - b), 0.);
	return fmin(a, b) - h*h*0.25/k;
}

int quickExp(int n, int p) {
    if(p==0) return 1;
    if(p%2==0) {
        int temp = quickExp(n, p/2);
        return temp*temp;
    }
    return n*quickExp(n, p-1);
}

uint8_t computeValue(int n, int x, int y, int z) {
	Vector3 coord = (Vector3){(double)x, (double)y, (double)z};
	
    double cTorus = n/2.;
    Vector3 posTorus = Vector3Subtract(coord, (Vector3){cTorus, cTorus, cTorus});
	double torus = torusSDF(posTorus, (Vector2){6., 3.5})/(sqrt(3))*127;

	double cBox = 2.*n/3.;
	Vector3 posBox = Vector3Subtract(coord, (Vector3){cBox, cBox, cBox});
	posBox = Vector3RotateByAxisAngle(posBox, (Vector3){1., 0., 0.}, PI/6);
	posBox = Vector3RotateByAxisAngle(posBox, (Vector3){0., 1., 0.}, PI/6);
	posBox = Vector3RotateByAxisAngle(posBox, (Vector3){0., 0., 1.}, PI/6);
    double box = boxSDF(posBox, (Vector3){6., 6., 6.}, 2.)/(sqrt(3))*127;

	double dist = smoothUnionSDF(box, torus, 20.);
	double rounded = dist >= 0 ? dist + 0.5 : dist - 0.5;
    uint8_t val = (uint8_t)(intClamp((int)rounded, -127, 127)+127);
	return val;
}

bool nodeEquality(Node* node1, Node* node2) {
	return node1->isLeaf	== node2->isLeaf
		&& node1->cache		== node2->cache
		&& node1->data000	== node2->data000
        && node1->data100   == node2->data100
        && node1->data010   == node2->data010
        && node1->data110   == node2->data110
        && node1->data001   == node2->data001
        && node1->data101   == node2->data101
        && node1->data011   == node2->data011
        && node1->data111   == node2->data111;
}

void freeNode(Node* node) {
    if(!node->isLeaf) {
        for(int i = 0; i < 8; i++) {
            freeNode(node->children[i]);
        }
    }
    free(node);
}

Node* createOctree(int p, int n, int x, int y, int z) {
	if(p==0) {
		Node* node = malloc(sizeof(Node));
		for(int i = 0; i<8; i++) {
			node->children[i] = NULL;
		}
		node->isLeaf = true;
		node->cache=0;
		node->data000=computeValue(n, x, y, z);
        node->data100=computeValue(n, x+1, y, z);
        node->data010=computeValue(n, x, y+1, z);
        node->data110=computeValue(n, x+1, y+1, z);
        node->data001=computeValue(n, x, y, z+1);
        node->data101=computeValue(n, x+1, y, z+1);
        node->data011=computeValue(n, x, y+1, z+1);
        node->data111=computeValue(n, x+1, y+1, z+1);
		return node;
	}
	else {
		int offset = 1<<(p-1);
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
			freeNode(node100);
			freeNode(node010);
			freeNode(node110);
			freeNode(node001);
			freeNode(node101);
			freeNode(node011);
			freeNode(node111);
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
			node->data000 = 0;
            node->data100 = 0;
            node->data010 = 0;
            node->data110 = 0;
            node->data001 = 0;
            node->data101 = 0;
            node->data011 = 0;
            node->data111 = 0;
			node->isLeaf=false;
			uint8_t cache = (node000->isLeaf ? 0x1 : 0x0)
				| (node100->isLeaf ? 0x1 : 0x0)<<1
				| (node010->isLeaf ? 0x1 : 0x0)<<2
				| (node110->isLeaf ? 0x1 : 0x0)<<3
				| (node001->isLeaf ? 0x1 : 0x0)<<4
				| (node101->isLeaf ? 0x1 : 0x0)<<5
				| (node011->isLeaf ? 0x1 : 0x0)<<6
				| (node111->isLeaf ? 0x1 : 0x0)<<7;
			node->cache = cache;
			return node;
		}
	}
}

NodeStack* createNodeStack() {
	NodeStack* s = malloc(sizeof(NodeStack));
	s->array = malloc(sizeof(Node*));
	s->capacity = 1;
	s->size = 0;
	return s;
}

void freeNodeStack(NodeStack* s) {
	free(s->array);
	free(s);
}

void appendNodeStack(NodeStack* s, Node* node) {
	if(s->size==s->capacity) {
		s->capacity *= 2;
		void* output = realloc(s->array, s->capacity*sizeof(Node*));
		assert(output != NULL);
		s->array = output;
	}
	s->array[s->size] = node;
	s->size += 1;
}

Node* popNodeStack(NodeStack* s) {
	assert(s->size > 0);
	s->size -= 1;
	Node* result = s->array[s->size];
	if(s->size <= s->capacity/4 && s->capacity > 1) {
		s->capacity = s->capacity/2;
		void* output = realloc(s->array, s->capacity*sizeof(Node*));
		assert(output!=NULL);
		s->array = output;		
	}
	return result;
}

NodeQueue* createNodeQueue() {
	NodeQueue* q = malloc(sizeof(NodeQueue));
	q->array = malloc(sizeof(Node*));
	q->capacity = 1;
	q->start = 0;
	q->size = 0;
	return q;
}

void freeNodeQueue(NodeQueue* q) {
	free(q->array);
	free(q);
}

void appendNodeQueue(NodeQueue* q, Node* node) {
	if(q->size == q->capacity) {
		q->capacity *= 2;
		void* output = realloc(q->array, q->capacity*sizeof(Node*));
		assert(output!=NULL);
		q->array = output;
		for(int i = 0; i<q->start; i++) {
			q->array[i+q->size] = q->array[i];
		}
	}
	q->array[(q->start+q->size)%q->capacity] = node;
	q->size += 1;
}

Node* popNodeQueue(NodeQueue* q) {
	Node* result = q->array[q->start];
	q->size -= 1;
	q->start = (q->start+1)%q->capacity;
	return result;
}

int count(Node* node) {
	if(node->isLeaf) return 1;
	int sum = 0;
	for(int i = 0; i<8; i++) {
		sum += count(node->children[i]);
	}
	return sum+1;
}

int fillBuffer(uint64_t* octreeBuffer, Node* octree) {
	NodeQueue* q = createNodeQueue();
	appendNodeQueue(q, octree);
	int nextAvailable = 0;
	while(q->size != 0) {
		Node* node = popNodeQueue(q);
		if(node->isLeaf) {
			uint64_t nodeInt = (uint64_t)node->data000
            | ((uint64_t)node->data100 << 8)
            | ((uint64_t)node->data010 << 16)
            | ((uint64_t)node->data110 << 24)
            | ((uint64_t)node->data001 << 32)
            | ((uint64_t)node->data101 << 40)
            | ((uint64_t)node->data011 << 48)
            | ((uint64_t)node->data111 << 56);
			octreeBuffer[nextAvailable] = nodeInt;
			nextAvailable++;
		}
		else {
			uint32_t childAddress = (uint32_t)(nextAvailable + q->size + 1);
			uint64_t nodeInt = ((uint64_t)node->cache << 24) | (childAddress & 0x00FFFFFFu);

			for(int i = 0; i<8; i++) {
				appendNodeQueue(q, node->children[i]);
			}
			octreeBuffer[nextAvailable] = nodeInt;
			nextAvailable++;
		}
	}
	freeNodeQueue(q);
	return nextAvailable;
}

int updateBuffer(uint64_t* octreeBuffer, Node* octree) {
	int size = fillBuffer(octreeBuffer, octree);
	return size;
}

int main ()
{
	FILE* data = fopen("data/octree.txt", "w");
	SetConfigFlags(FLAG_WINDOW_HIGHDPI);
	InitWindow(1280, 800, "Test");
	
	ToggleFullscreen();
	float ratio = (float)GetScreenWidth()/GetScreenHeight();

	Shader shader = LoadShader(0, "ressources/shaderOctreeFaster.glsl");
	RenderTexture2D target = LoadRenderTexture(GetScreenWidth(), GetScreenHeight());

	// Uniform locations
	int ratioLoc = GetShaderLocation(shader, "ratio");
	int cameraForwardLoc = GetShaderLocation(shader, "cameraForward");
	int cameraRightLoc = GetShaderLocation(shader, "cameraRight");
	int cameraUpLoc = GetShaderLocation(shader, "cameraUp");
	int positionLoc = GetShaderLocation(shader, "position");
	int startPointLoc = GetShaderLocation(shader, "startPoint");
	int voxelSizeLoc = GetShaderLocation(shader, "voxelSize");
	int pLoc = GetShaderLocation(shader, "p");
	int fovLoc = GetShaderLocation(shader, "fov");
	int modeLoc = GetShaderLocation(shader, "mode");

	float fov = 1.2;
	Vector3 startPoint = (Vector3){0., 0., 0.};
	float voxelSize = 1.;

	int sampleFrameNumber = 1000;
	int circleRadius = 16.;

    int p = 5;
	int n = 1<<p;

	int size = (quickExp(8, p+1) - 1) / 7;
    uint64_t* octreeBuffer = malloc(size*sizeof(uint64_t));
	Node* octree = createOctree(p, n, 0, 0, 0);
	int bufferSize = updateBuffer(octreeBuffer, octree);
	int numberNodes = count(octree);
	printf("Node number : %d\n", numberNodes);
	printf("Estimated ssbo size : %dko\n", 64*numberNodes/8000);
	int ssboOctree = rlLoadShaderBuffer(bufferSize* sizeof(uint64_t), octreeBuffer, RL_DYNAMIC_READ);
	rlBindShaderBuffer(ssboOctree, 0);

	bool updateEnabled = false;
	int mode = 3;
	int modeNumber = 5;

	SetShaderValue(shader, fovLoc, &fov, SHADER_UNIFORM_FLOAT);
	SetShaderValue(shader, startPointLoc, &startPoint, SHADER_UNIFORM_VEC3);
	SetShaderValue(shader, voxelSizeLoc, &voxelSize, SHADER_UNIFORM_FLOAT);
	SetShaderValue(shader, pLoc, &p, SHADER_UNIFORM_INT);

	Vector3 pos = {-1., -1., n/2};
	
	DisableCursor();

	SetTargetFPS(1000);

	double pitch = 0.;
	double yaw = 0.;
	double roll = 0.;
	while (!WindowShouldClose())
	{
		if (updateEnabled) {
		}
		Vector2 delta = GetMouseDelta();
		pitch -= (double)delta.y*GetFrameTime()*0.5;
		pitch = Clamp(pitch, -PI/3, PI/3);
		yaw += (double)delta.x*GetFrameTime()*0.5;
		Vector3 vectForward = (Vector3) {
			cos(pitch)*cos(yaw),
			cos(pitch)*sin(yaw),
			sin(pitch)
		};
		Vector3 vectY = Vector3Normalize(Vector3CrossProduct(vectForward, (Vector3){0., 0., -1.}));
		Vector3 vectA = Vector3CrossProduct(vectForward, vectY);
		Vector3 vectRight = Vector3Add(
			Vector3Scale(vectY, cos(roll)),
			Vector3Scale(vectA, sin(roll))
		);
		Vector3 vectUp = Vector3CrossProduct(vectForward, vectRight);

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
	free(octreeBuffer);
	freeNode(octree);
	return 0;
}