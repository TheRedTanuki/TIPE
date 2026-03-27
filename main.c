#include <raylib.h>
#include <assert.h>
#include <stdlib.h>
#include <stdio.h>
#include <stdbool.h>
#include <math.h>
//gcc main.c -o main -lraylib -lm -lpthread -ldl -lrt -lX11

typedef struct
{
	double** array;
	int m;
	int p;
} mat;

void printMat(mat* mat) {
	for(int i = 0; i<mat->m; i++) {
		for(int j = 0; j<mat->p; j++) {
			printf("%f ", mat->array[i][j]);
		}
		printf("\n");
	}
}

mat mult(mat* m1, mat* m2) {
	assert(m1->p==m2->m);
	mat matrix;
	matrix.m = m1->m;
	matrix.p = m2->p;
	matrix.array = malloc(sizeof(double*) * m1->m);
	for(int i = 0; i<m1->m; i++) {
		matrix.array[i] = malloc(sizeof(double) * m2->p);
		for(int j = 0; j<m2->p; j++) {
			matrix.array[i][j] = 0;
			for(int k = 0; k<m1->p; k++) {
				matrix.array[i][j] += m1->array[i][k] * m2->array[k][j];
			}
		}
	}
	return matrix;
}

mat array_to_mat(double** array, int m, int p) {
	mat matrix = {.array = array, .m = m, .p = p};
	return matrix;
}

mat pitch3d_mat(double pitch) {
	double** array = malloc(3*sizeof(double*));
	for(int i = 0; i<3; i++) {
		array[i] = malloc(3*sizeof(double));
	}
	array[0][0] = 1.;
	array[0][1] = 0.;
	array[0][2] = 0.;

	array[1][0] = 0.;
	array[1][1] = cos(pitch);
	array[1][2] = -sin(pitch);

	array[2][0] = 0.;
	array[2][1] = sin(pitch);
	array[2][2] = cos(pitch);
	mat matrix = {
		.array = array,
		.m = 3,
		.p = 3
	};
	return matrix;
}

mat yaw3d_mat(double yaw) {
	double** array = malloc(3*sizeof(double*));
	for(int i = 0; i<3; i++) {
		array[i] = malloc(3*sizeof(double));
	}
	array[0][0] = cos(yaw);
	array[0][1] = 0.;
	array[0][2] = sin(yaw);

	array[1][0] = 0.;
	array[1][1] = 1.;
	array[1][2] = 0.;

	array[2][0] = -sin(yaw);
	array[2][1] = 0.;
	array[2][2] = cos(yaw);

	mat matrix = {
		.array = array,
		.m = 3,
		.p = 3
	};
	return matrix;
}

mat roll3d_mat(double roll) {
	double** array = malloc(3*sizeof(double*));
	for(int i = 0; i<3; i++) {
		array[i] = malloc(3*sizeof(double));
	}
	array[0][0] = cos(roll);
	array[0][1] = -sin(roll);
	array[0][2] = 0.;

	array[1][0] = sin(roll);
	array[1][1] = cos(roll);
	array[1][2] = 0.;

	array[2][0] = 0.;
	array[2][1] = 0.;
	array[2][2] = 1.;

	mat matrix = {
		.array = array,
		.m = 3,
		.p = 3
	};
	return matrix;
}

mat rotation3d_mat(double pitch, double yaw, double roll) {
	mat pitch_mat = pitch3d_mat(pitch);
	mat yaw_mat = yaw3d_mat(yaw);
	mat roll_mat = roll3d_mat(roll);
	mat yaw_roll_mat = mult(&yaw_mat, &roll_mat);

	return mult(&pitch_mat, &yaw_roll_mat);
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

Vector3 scalarMult(Vector3 v, double a) {
	return (Vector3) {v.x*a, v.y*a, v.z*a};
}

Vector3 vectAdd(Vector3 v1, Vector3 v2) {
	return (Vector3){v1.x + v2.x, v1.y + v2.y, v1.z + v2.z};
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
	double** direction_array = malloc(3*sizeof(double));
	for(int i = 0; i<3; i++) {
		direction_array[i] = malloc(sizeof(double));
		direction_array[i][0] = 1.;
	}
	mat direction_default = {.array = direction_array, .m = 3, .p = 1};
	mat direction_mat;
	DisableCursor();

	double pitch = 0.0;
	double yaw = 0.0;
	double roll = 0.0;

	while (!WindowShouldClose())
	{
		
		Vector2 delta = GetMouseDelta();
		
		pitch += (double)delta.y*0.002;
		if(pitch > 1.5) pitch = 1.5;
		if(pitch < -1.5) pitch = -1.5;
		yaw -= (double)delta.x*0.002;
		
		mat rotation_mat = rotation3d_mat(pitch, yaw, roll);
		direction_mat = mult(&rotation_mat, &direction_default);

		Vector3 forward = normalize((Vector3){direction_mat.array[0][0], direction_mat.array[1][0], direction_mat.array[2][0]});
		Vector3 right = normalize(cross(forward, (Vector3){0.0, 1.0, 0.0}));
		Vector3 up = cross(right, forward);

		if(IsKeyDown(KEY_W)) pos = vectAdd(scalarMult(forward, 0.5), pos);
		if(IsKeyDown(KEY_S)) pos = vectAdd(scalarMult(forward, -0.5), pos);
		if(IsKeyDown(KEY_A)) pos = vectAdd(scalarMult(right, -0.5), pos);
		if(IsKeyDown(KEY_D)) pos = vectAdd(scalarMult(right, 0.5), pos);
		
		SetShaderValue(shader, ratioLoc, &ratio, SHADER_UNIFORM_FLOAT);
		SetShaderValue(shader, cameraForwardLoc, &forward, SHADER_UNIFORM_VEC3);
		SetShaderValue(shader, cameraRightLoc, &right, SHADER_UNIFORM_VEC3);
		SetShaderValue(shader, cameraUpLoc, &up, SHADER_UNIFORM_VEC3);
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
