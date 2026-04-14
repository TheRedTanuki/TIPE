#define GRAPHICS_API_OPENGL_43
#include <raylib.h>
#include <assert.h>
#include <stdlib.h>
#include <stdio.h>
#include <stdbool.h>
#include <math.h>
#include <stdint.h>
#include <rlgl.h>
//gcc main.c -o main -lraylib -lm -lpthread -ldl -lrt -lX11

// Quaternion functions

Vector3 normalizeV3(Vector3 v) {
	double norm = sqrt(v.x*v.x + v.y*v.y + v.z*v.z);
	return (Vector3){v.x/norm, v.y/norm, v.z/norm};
}

Quaternion normalizeQ(Quaternion q) {
	double norm = sqrt(q.x*q.x + q.y*q.y + q.z*q.z + q.w*q.w);
	return (Quaternion){q.x/norm, q.y/norm, q.z/norm, q.w/norm};
}

Quaternion mult(Quaternion q1, Quaternion q2) {
	Quaternion res = {
		q1.x * q2.x - q1.y * q2.y - q1.z * q2.z - q1.w * q2.w,
		q1.x * q2.y + q1.y * q2.x + q1.z * q2.w - q1.w * q2.z,
		q1.x * q2.z - q1.y * q2.w + q1.z * q2.x + q1.w * q2.y,
		q1.x * q2.w + q1.y * q2.z - q1.z * q2.y + q1.w * q2.x
	};
	return res;
}

Quaternion quatAdd(Quaternion v1, Quaternion v2) {
	return (Quaternion) {v1.x + v2.x, v1.y + v2.y, v1.z + v2.z, v1.w + v2.w};
}

Quaternion inverse(Quaternion q) {
	return (Quaternion){q.x, -q.y, -q.z, -q.w};
}

Quaternion rotateQuat(Quaternion p, Quaternion q) {
	return mult(q, mult(p, inverse(q)));
}

Quaternion rotationQuat(Quaternion axis, double angle) {
	double c = cos(angle/2);
	double s = sin(angle/2);
	return (Quaternion){c, s*axis.y, s*axis.z, s*axis.w};
}

Vector3 quatToVect3(Quaternion q) {
	return (Vector3){q.y, q.z, q.w};
}

Vector3 vect3Add(Vector3 v1, Vector3 v2) {
	return (Vector3) {v1.x + v2.x, v1.y + v2.y, v1.z + v2.z};
}

Vector3 scalarMultVect3(Vector3 v, double a) {
	return (Vector3) {v.x*a, v.y*a, v.z*a};
}


Vector3 cross(Vector3 v1, Vector3 v2) {
	Vector3 res = {0};
	res.x = v1.y*v2.z - v1.z*v2.y;
	res.y = v1.z*v2.x - v1.x*v2.z;
	res.z = v1.x*v2.y - v1.y*v2.x;
	return res;
}

bool*** create3DBuffer(int n) {
	bool*** voxelBuffer = malloc(sizeof(bool**)*n);
	for(int i = 0; i<n; i++) {
		voxelBuffer[i] = malloc(n*sizeof(bool*)*n);
		for(int j = 0; j<n; j++) {
			voxelBuffer[i][j] = calloc(n, sizeof(bool));
		}
	}
	return voxelBuffer;
}

/*Image convertBoolBuffToImage(bool* buffer, int n) {
	int size = (n*n*n-1)/32+1;
	Image image = GenImageColor(size, 1, BLACK);
	uint32_t bool_temp;
	Color color_temp;
	for(int i = 0; i<size; i++) {
		bool_temp = 0;

		int maxbits = i<(size-1) ? 32 : (32-(size*32-n*n*n));
		for(int j = 0; j<maxbits; j++) {
			bool_temp |= (buffer[j+i*32]? 1u : 0u)<<j;
		}
		memcpy(&color_temp, &bool_temp, sizeof(uint32_t));
		ImageDrawPixel(&image, i, 0, color_temp);
	}
	return image;
}*/

int main ()
{
	SetConfigFlags(FLAG_WINDOW_HIGHDPI);
	InitWindow(1280, 800, "Test");
	
	ToggleFullscreen();
	float ratio = (float)GetScreenWidth()/GetScreenHeight();

	Shader shader = LoadShader(0, "ressources/shader.glsl");
	RenderTexture2D target = LoadRenderTexture(GetScreenWidth(), GetScreenHeight());

	// Uniform locations
	int ratioLoc = GetShaderLocation(shader, "ratio");
	int cameraForwardLoc = GetShaderLocation(shader, "cameraForward");
	int cameraRightLoc = GetShaderLocation(shader, "cameraRight");
	int cameraUpLoc = GetShaderLocation(shader, "cameraUp");
	int positionLoc = GetShaderLocation(shader, "position");
	int nLoc = GetShaderLocation(shader, "n");
	int fovLoc = GetShaderLocation(shader, "fov");

	int n = 32;
	float fov = 1.2;
	// int size = (n*n*n-1)/8+1;
	uint8_t* voxelArray = calloc(n, sizeof(uint8_t));
	int ssbo = rlLoadShaderBuffer(n, voxelArray, RL_STATIC_READ);
	rlBindShaderBuffer(ssbo, 0);

	SetShaderValue(shader, nLoc, &n, SHADER_UNIFORM_INT);
	SetShaderValue(shader, fovLoc, &fov, SHADER_UNIFORM_FLOAT);

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
		
		Vector2 delta = GetMouseDelta();
		pitch += (double)delta.y*GetFrameTime()*0.5;
		yaw += (double)delta.x*GetFrameTime()*0.5;
		//roll += 0.02*((IsKeyDown(KEY_Q) ? 1 : 0) + (IsKeyDown(KEY_E) ? -1 : 0));

		Quaternion rQuat = mult(rotationQuat((Quaternion){0., 0., 0., 1.}, yaw), mult(rotationQuat((Quaternion){0., 0., 1., 0.}, pitch), rotationQuat((Quaternion){0., 1., 0., 0.}, roll)));
		forward = rotateQuat((Quaternion){0., 1., 0., 0.}, rQuat);
		right = rotateQuat((Quaternion){0., 0., 1., 0.}, rQuat);
		up = rotateQuat((Quaternion){0., 0., 0., 1.}, rQuat);
		Vector3 vectForward = quatToVect3(forward);
		Vector3 vectRight = quatToVect3(right);
		Vector3 vectUp = quatToVect3(up);

		if(IsKeyDown(KEY_W)) pos = vect3Add(scalarMultVect3(vectForward, GetFrameTime()*25), pos);
		if(IsKeyDown(KEY_S)) pos = vect3Add(scalarMultVect3(vectForward, -GetFrameTime()*25), pos);
		if(IsKeyDown(KEY_A)) pos = vect3Add(scalarMultVect3(vectRight, -GetFrameTime()*25), pos);
		if(IsKeyDown(KEY_D)) pos = vect3Add(scalarMultVect3(vectRight, GetFrameTime()*25), pos);
		if(IsKeyDown(KEY_SPACE)) pos = vect3Add(scalarMultVect3(vectUp, GetFrameTime()*10), pos);
		if(IsKeyDown(KEY_LEFT_SHIFT)) pos = vect3Add(scalarMultVect3(vectUp, -GetFrameTime()*10), pos);
		
		SetShaderValue(shader, ratioLoc, &ratio, SHADER_UNIFORM_FLOAT);
		SetShaderValue(shader, cameraForwardLoc, &vectForward, SHADER_UNIFORM_VEC3);
		SetShaderValue(shader, cameraRightLoc, &vectRight, SHADER_UNIFORM_VEC3);
		SetShaderValue(shader, cameraUpLoc, &vectUp, SHADER_UNIFORM_VEC3);
		SetShaderValue(shader, positionLoc, &pos, SHADER_UNIFORM_VEC3);		

		BeginTextureMode(target);
			DrawRectangle(0, 0, GetScreenWidth(), GetScreenHeight(), RAYWHITE);
		EndTextureMode();

		BeginDrawing();

			ClearBackground(RAYWHITE);
			BeginShaderMode(shader);
				DrawTextureRec(target.texture, (Rectangle){ 0, 0, (float)target.texture.width, (float)-target.texture.height}, (Vector2){0,0}, RAYWHITE);
			EndShaderMode();
		
		EndDrawing();
		printf("%d | %lf x : %lf y : %lf z\n", GetFPS(), pos.x, pos.y, pos.z);
	}

	UnloadShader(shader);
	CloseWindow();
	return 0;
}
