#include <raylib.h>
#include <assert.h>
#include <stdlib.h>
#include <stdio.h>
#include <stdbool.h>
#include <math.h>
//gcc main.c -o main -lraylib -lm -lpthread -ldl -lrt -lX11

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

Vector3 vect3Add(Vector3 v1, Vector3 v2) {
	return (Vector3) {v1.x + v2.x, v1.y + v2.y, v1.z + v2.z};
}

Vector3 scalarMultVect3(Vector3 v, double a) {
	return (Vector3) {v.x*a, v.y*a, v.z*a};
}

Vector3 quatToVect3(Quaternion q) {
	return (Vector3){q.y, q.z, q.w};
}

Quaternion rotationQuat(Quaternion axis, double angle) {
	double c = cos(angle/2);
	double s = sin(angle/2);
	return (Quaternion){c, s*axis.y, s*axis.z, s*axis.w};
}

Quaternion inverse(Quaternion q) {
	return (Quaternion){q.x, -q.y, -q.z, -q.w};
}

Vector3 cross(Vector3 v1, Vector3 v2) {
	Vector3 res = {0};
	res.x = v1.y*v2.z - v1.z*v2.y;
	res.y = v1.z*v2.x - v1.x*v2.z;
	res.z = v1.x*v2.y - v1.y*v2.x;
	return res;
}

Vector3 normalize(Vector3 v) {
	double norm = sqrt(v.x*v.x + v.y*v.y + v.z*v.z);
	return (Vector3){v.x/norm, v.y/norm, v.z/norm};
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

int main ()
{
	SetConfigFlags(FLAG_VSYNC_HINT | FLAG_WINDOW_HIGHDPI);

	InitWindow(1280, 800, "Test");
	ToggleFullscreen();
	float ratio = (float)GetScreenWidth()/GetScreenHeight();
	printf("%lf\n", ratio);

	Shader shader = LoadShader(0, "ressources/shader.glsl");
	RenderTexture2D target = LoadRenderTexture(GetScreenWidth(), GetScreenHeight());

	// Uniform locations
	int ratioLoc = GetShaderLocation(shader, "ratio");
	int cameraForwardLoc = GetShaderLocation(shader, "cameraForward");
	int cameraRightLoc = GetShaderLocation(shader, "cameraRight");
	int cameraUpLoc = GetShaderLocation(shader, "cameraUp");
	int positionLoc = GetShaderLocation(shader, "position");
	int voxelArrayLoc = GetShaderLocation(shader, "voxelArray");
	int nLoc = GetShaderLocation(shader, "n");

	int n = 32;
	bool*** voxelArray = create3DBuffer(n);
	Image img = GenImageColor(n, n*n, BLACK);

	for(int z=0; z<n; z++){
		for(int y=0; y<n; y++){
			for(int x=0; x<n; x++){
				Color c = voxelArray[x][y][z] ? WHITE : BLACK;
				ImageDrawPixel(&img, x, y + z*n, c);
			}
		}
	}

	Texture2D voxTex = LoadTextureFromImage(img);
	SetTextureFilter(voxTex, TEXTURE_FILTER_POINT);
	SetShaderValue(shader, nLoc, &n, SHADER_UNIFORM_INT);

	Vector3 pos = {0., 0., -2.};
	Quaternion forward = {0., 1., 0., 0.};
	Quaternion right = {0., 0., 1., 0.};
	Quaternion up = {0., 0., 0., 1.};
	DisableCursor();

	double pitch = 0.0;
	double yaw = 0.0;
	double roll = 0.0;

	while (!WindowShouldClose())
	{
		
		Vector2 delta = GetMouseDelta();
		
		pitch = (double)delta.y*0.002;
		yaw = (double)delta.x*0.002;
		roll = 0.02*(IsKeyDown(KEY_Q)?1:0 + IsKeyDown(KEY_E)?-1:0);

		Quaternion rQuat = mult(mult(rotationQuat(right, pitch), rotationQuat(up, yaw)), rotationQuat(forward, roll));
		Quaternion rQuatInv = inverse(rQuat);
		forward = mult(rQuat, mult(forward, rQuatInv));
		right = mult(rQuat, mult(right, rQuatInv));
		up = mult(rQuat, mult(up, rQuatInv));
		Vector3 vectForward = quatToVect3(forward);
		Vector3 vectRight = quatToVect3(right);
		Vector3 vectUp = quatToVect3(up);;

		if(IsKeyDown(KEY_W)) pos = vect3Add(scalarMultVect3(vectForward, 0.5), pos);
		if(IsKeyDown(KEY_S)) pos = vect3Add(scalarMultVect3(vectForward, -0.5), pos);
		if(IsKeyDown(KEY_A)) pos = vect3Add(scalarMultVect3(vectRight, -0.5), pos);
		if(IsKeyDown(KEY_D)) pos = vect3Add(scalarMultVect3(vectRight, 0.5), pos);
		
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
	}

	UnloadShader(shader);
	CloseWindow();
	return 0;
}
