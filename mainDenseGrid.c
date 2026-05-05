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
// gcc mainDenseGrid.c -O3 -o mainDenseGrid -lraylib -lm -lpthread -ldl -lrt -lX11 && ./mainDenseGrid

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

void updateBuffer(uint32_t* voxelArray, int n, double time) {
	for(int k = 0; k<n; k++) {
		for(int j = 0; j<n; j++) {
			for(int i = 0; i<n; i++) {
				int index = i+n*j+n*n*k;
				double movingCenter = (n-1+sin(time*0.5))/2.;
				double c = (n-1)/2.;
				Vector3 pos = (Vector3){(double)i-movingCenter, (double)j-c, (double)k-c};
				double dist = sdf(pos, (Vector2){6., 3.})/(sqrt(2))*127;
				uint32_t val = (uint32_t)(intClamp((int)dist, -127, 127)+127);
				uint32_t shift = (index % 4) * 8;
				uint32_t mask  = 0xFFu << shift;

				voxelArray[index/4] =
					(voxelArray[index/4] & ~mask) |
					(val << shift);
			}
		}
	}
}

int main ()
{
	SetConfigFlags(FLAG_WINDOW_HIGHDPI);
	InitWindow(1280, 800, "Test");
	
	ToggleFullscreen();
	float ratio = (float)GetScreenWidth()/GetScreenHeight();

	Shader shader = LoadShader(0, "ressources/shaderDenseGrid.glsl");
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

	int n = 32;
	uint32_t* voxelArray = calloc((n*n*n-1)/4+1, sizeof(uint32_t));
	updateBuffer(voxelArray, n, GetTime());
	int ssbo = rlLoadShaderBuffer(((n*n*n-1)/4+1)*sizeof(uint32_t), voxelArray, RL_DYNAMIC_READ);
	rlBindShaderBuffer(ssbo, 0);
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
			updateBuffer(voxelArray, n, GetTime());
			rlUpdateShaderBuffer(ssbo, voxelArray, ((n*n*n-1)/4+1)*sizeof(uint32_t), 0);
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
	free(voxelArray);
	return 0;
}
