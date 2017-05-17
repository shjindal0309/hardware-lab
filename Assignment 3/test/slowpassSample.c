/* tested on Fedora 24, 64 bit machine using gcc 6.31 */


#include <string.h>
#include <stdio.h>
#include <math.h>
#include <stdlib.h>

#define MAX_HEIGHT 256
#define MAX_WIDTH 256

int temp;

typedef struct BMP{

	unsigned short bType;           /* Magic number for file */
	unsigned int   bSize;           /* Size of file */
	unsigned short bReserved1;      /* Reserved */
	unsigned short bReserved2;      /* ... */
	unsigned int   bOffBits;        /* Offset to bitmap data */

	unsigned int  bISize;           /* Size of info header */
	unsigned int  bWidth;          /* Width of image */
	unsigned int   bHeight;         /* Height of image */
	unsigned short bPlanes;         /* Number of color planes */
	unsigned short bBitCount;       /* Number of bits per pixel */
	unsigned int  bCompression;    /* Type of compression to use */
	unsigned int  bSizeImage;      /* Size of image data */
	int           bXPelsPerMeter;  /* X pixels per meter */
	int      	    bYPelsPerMeter;  /* Y pixels per meter */
	unsigned int   bClrUsed;        /* Number of colors used */
	unsigned int   bClrImportant;   /* Number of important colors */
}BMP;

//void RGB2YUV();
int Read_BMP_Header(char *filename, int *h, int *w,BMP *bmp)
{

	FILE *f;
	int *p;
	f=fopen("test.bmp","r");
	printf("\nReading BMP Header ");
	fread(&bmp->bType,sizeof(unsigned short),1,f);
	p=(int *)bmp;
	fread(p+1,sizeof(BMP)-4,1,f);
	if (bmp->bType != 19778) {
		printf("Error, not a BMP file!\n");
		return 0;
	}

	*w = bmp->bWidth;
	*h = bmp->bHeight;
	return 1;
}

void Read_BMP_Data(char *filename,int *h,int *w,BMP *bmp)
{

	int i,j,i1,H,W,Wp,PAD;
	unsigned char *RGB;
	FILE *f;
	printf("\nReading BMP Data ");
	f=fopen(filename,"r");
	fseek(f, 0, SEEK_SET);
	fseek(f, bmp->bOffBits, SEEK_SET);
	W = bmp->bWidth;
	H = bmp->bHeight;
	printf("\nheight = %d width= %d \n",H,W);
	PAD = (3 * W) % 4 ? 4 - (3 * W) % 4 : 0;
	Wp = 3 * W + PAD;
	RGB = (unsigned char *)malloc(Wp*H *sizeof(unsigned char));
	for(i=0;i<Wp*H;i++) RGB[i]=0;
	fread(RGB, sizeof(unsigned char), Wp * H, f);

	FILE **output=(FILE**)malloc(sizeof(FILE*));
	char hex[3][3]; //hex[0] means B hex[1] means G hex[2] means R
	output[0]=fopen("string0.sh","w");
	output[1]=fopen("string1.sh","w");
	output[2]=fopen("string2.sh","w");
	if(output[0]==NULL || output[1]==NULL || output[2]==NULL)
	{
		puts("Cannot open output file");
		exit(1);
	}
	
	fprintf(output[0],"cd C:/makestuff/libs/libfpgalink-20120621\n");
	fprintf(output[1],"cd C:/makestuff/libs/libfpgalink-20120621\n");
	fprintf(output[2],"cd C:/makestuff/libs/libfpgalink-20120621\n");
	//traversing row wise starting from (1,1) to (256,256)
	//string0 blue
	//string1 green
	//string2 red
	
	i1=0;
	fprintf(output[0],"./win32/rel/flcli -v 1443:0007 -a \"w1 ");
	fprintf(output[1],"./win32/rel/flcli -v 1443:0007 -a \"w11 ");
	fprintf(output[2],"./win32/rel/flcli -v 1443:0007 -a \"w21 ");
	for (i = 0; i < H; i+=3){
		for (j = 0; j < W; j+=3){
			i1=i*(Wp)+j*3;
			sprintf(hex[0],"%02x",RGB[i1]);
			fprintf(output[0],hex[0]);

			sprintf(hex[1],"%02x",RGB[i1+1]);
			fprintf(output[1],hex[1]);

			sprintf(hex[2],"%02x",RGB[i1+2]);
			fprintf(output[2],hex[2]);
		}
	}

	i1=0;
	fprintf(output[0],"\"\n./win32/rel/flcli -v 1443:0007 -a \"w2 ");
	fprintf(output[1],"\"\n./win32/rel/flcli -v 1443:0007 -a \"w12 ");
	fprintf(output[2],"\"\n./win32/rel/flcli -v 1443:0007 -a \"w22 ");
	for (i = 1; i < H; i+=3){
		for (j = 0; j < W; j+=3){
			i1=i*(Wp)+j*3;
			sprintf(hex[0],"%02x",RGB[i1]);
			fprintf(output[0],hex[0]);

			sprintf(hex[1],"%02x",RGB[i1+1]);
			fprintf(output[1],hex[1]);

			sprintf(hex[2],"%02x",RGB[i1+2]);
			fprintf(output[2],hex[2]);
		}
	}

	i1=0;
	fprintf(output[0],"\"\n./win32/rel/flcli -v 1443:0007 -a \"w3 ");
	fprintf(output[1],"\"\n./win32/rel/flcli -v 1443:0007 -a \"w13 ");
	fprintf(output[2],"\"\n./win32/rel/flcli -v 1443:0007 -a \"w23 ");
	for (i = 2; i < H; i+=3){
		for (j = 0; j < W; j+=3){
			i1=i*(Wp)+j*3;
			sprintf(hex[0],"%02x",RGB[i1]);
			fprintf(output[0],hex[0]);

			sprintf(hex[1],"%02x",RGB[i1+1]);
			fprintf(output[1],hex[1]);

			sprintf(hex[2],"%02x",RGB[i1+2]);
			fprintf(output[2],hex[2]);
		}
	}

	i1=0;
	fprintf(output[0],"\"\n./win32/rel/flcli -v 1443:0007 -a \"w4 ");
	fprintf(output[1],"\"\n./win32/rel/flcli -v 1443:0007 -a \"w14 ");
	fprintf(output[2],"\"\n./win32/rel/flcli -v 1443:0007 -a \"w24 ");
	for (i = 0; i < H; i+=3){
		for (j = 1; j < W; j+=3){
			i1=i*(Wp)+j*3;
			sprintf(hex[0],"%02x",RGB[i1]);
			fprintf(output[0],hex[0]);

			sprintf(hex[1],"%02x",RGB[i1+1]);
			fprintf(output[1],hex[1]);

			sprintf(hex[2],"%02x",RGB[i1+2]);
			fprintf(output[2],hex[2]);
		}
	}

	i1=0;
	fprintf(output[0],"\"\n./win32/rel/flcli -v 1443:0007 -a \"w5 ");
	fprintf(output[1],"\"\n./win32/rel/flcli -v 1443:0007 -a \"w15 ");
	fprintf(output[2],"\"\n./win32/rel/flcli -v 1443:0007 -a \"w25 ");
	for (i = 1; i < H; i+=3){
		for (j = 1; j < W; j+=3){
			i1=i*(Wp)+j*3;
			sprintf(hex[0],"%02x",RGB[i1]);
			fprintf(output[0],hex[0]);

			sprintf(hex[1],"%02x",RGB[i1+1]);
			fprintf(output[1],hex[1]);

			sprintf(hex[2],"%02x",RGB[i1+2]);
			fprintf(output[2],hex[2]);
		}
	}

	i1=0;
	fprintf(output[0],"\"\n./win32/rel/flcli -v 1443:0007 -a \"w6 ");
	fprintf(output[1],"\"\n./win32/rel/flcli -v 1443:0007 -a \"w16 ");
	fprintf(output[2],"\"\n./win32/rel/flcli -v 1443:0007 -a \"w26 ");
	for (i = 2; i < H; i+=3){
		for (j = 1; j < W; j+=3){
			i1=i*(Wp)+j*3;
			sprintf(hex[0],"%02x",RGB[i1]);
			fprintf(output[0],hex[0]);

			sprintf(hex[1],"%02x",RGB[i1+1]);
			fprintf(output[1],hex[1]);

			sprintf(hex[2],"%02x",RGB[i1+2]);
			fprintf(output[2],hex[2]);
		}
	}

	i1=0;
	fprintf(output[0],"\"\n./win32/rel/flcli -v 1443:0007 -a \"w7 ");
	fprintf(output[1],"\"\n./win32/rel/flcli -v 1443:0007 -a \"w17 ");
	fprintf(output[2],"\"\n./win32/rel/flcli -v 1443:0007 -a \"w27 ");
	for (i = 0; i < H; i+=3){
		for (j = 2; j < W; j+=3){
			i1=i*(Wp)+j*3;
			sprintf(hex[0],"%02x",RGB[i1]);
			fprintf(output[0],hex[0]);

			sprintf(hex[1],"%02x",RGB[i1+1]);
			fprintf(output[1],hex[1]);

			sprintf(hex[2],"%02x",RGB[i1+2]);
			fprintf(output[2],hex[2]);
		}
	}

	i1=0;
	fprintf(output[0],"\"\n./win32/rel/flcli -v 1443:0007 -a \"w8 ");
	fprintf(output[1],"\"\n./win32/rel/flcli -v 1443:0007 -a \"w18 ");
	fprintf(output[2],"\"\n./win32/rel/flcli -v 1443:0007 -a \"w28 ");
	for (i = 1; i < H; i+=3){
		for (j = 2; j < W; j+=3){
			i1=i*(Wp)+j*3;
			sprintf(hex[0],"%02x",RGB[i1]);
			fprintf(output[0],hex[0]);

			sprintf(hex[1],"%02x",RGB[i1+1]);
			fprintf(output[1],hex[1]);

			sprintf(hex[2],"%02x",RGB[i1+2]);
			fprintf(output[2],hex[2]);
		}
	}

	i1=0;
	fprintf(output[0],"\"\n./win32/rel/flcli -v 1443:0007 -a \"w9 ");
	fprintf(output[1],"\"\n./win32/rel/flcli -v 1443:0007 -a \"w19 ");
	fprintf(output[2],"\"\n./win32/rel/flcli -v 1443:0007 -a \"w29 ");
	for (i = 2; i < H; i+=3){
		for (j = 2; j < W; j+=3){
			i1=i*(Wp)+j*3;
			sprintf(hex[0],"%02x",RGB[i1]);
			fprintf(output[0],hex[0]);

			sprintf(hex[1],"%02x",RGB[i1+1]);
			fprintf(output[1],hex[1]);

			sprintf(hex[2],"%02x",RGB[i1+2]);
			fprintf(output[2],hex[2]);
		}
	}
	fprintf(output[0],"\"");
	fprintf(output[1],"\"");
	fprintf(output[2],"\"");

	
	fclose(output[0]);
	fclose(output[1]);
	fclose(output[2]);


	FILE *read=(FILE**)malloc(sizeof(FILE*));
	
	read[0]=fopen("blue_write.sh","w");
	read[1]=fopen("green_write.sh","w");
	read[2]=fopen("red_write.sh","w");
	if(read[0]==NULL || read[1]==NULL || read[2]==NULL)
	{
		puts("Cannot open read file");
		exit(1);
	}
	i1=0;
	fprintf(read[0],"./win32/rel/flcli -v 1443:0007 -a \"");
	fprintf(read[1],"./win32/rel/flcli -v 1443:0007 -a \"");
	fprintf(read[2],"./win32/rel/flcli -v 1443:0007 -a \"");

	int k;
	char name[3][9]={"blue.txt","green.txt","red.txt"};
	for(k=0; k < 3; k++)
	{
		int mark=10*k+1;
		for(i=0; i < H; i+=1)
		{
			for (j = 0; j < W; j+=3){
				fputs("r",read[k]);
				fputs(mark,read[k])
				fputs(" 1 \"name[k]\";",read[k]);
				fputs("r",read[k]);
				fputs(mark+1,read[k])
				fputs(" 1 \"name[k]\";",read[k]);
				fputs("r",read[k]);
				fputs(mark+2,read[k])
				fputs(" 1 \"name[k]\";",read[k]);				
			}
			for (j = 0; j < W; j+=3){
				fputs("r",read[k]);
				fputs(mark+3,read[k])
				fputs(" 1 \"name[k]\";",read[k]);
				fputs("r",read[k]);
				fputs(mark+4,read[k])
				fputs(" 1 \"name[k]\";",read[k]);
				fputs("r",read[k]);
				fputs(mark+5,read[k])
				fputs(" 1 \"name[k]\";",read[k]);				
			}
			for (j = 0; j < W; j+=3){
				fputs("r",read[k]);
				fputs(mark+6,read[k])
				fputs(" 1 \"name[k]\";",read[k]);
				fputs("r",read[k]);
				fputs(mark+7,read[k])
				fputs(" 1 \"name[k]\";",read[k]);
				fputs("r",read[k]);
				fputs(mark+8,read[k])
				fputs(" 1 \"name[k]\";",read[k]);				
			}
		}
	}

	//Start connection with FPGA
	char cmd[]="sh fpga-link_init.sh";
	system(cmd);
	//Send data to FPGA
	char cmd0[]="sh string0.sh";
	system(cmd0);
	char cmd1[]="sh string1.sh";
	system(cmd1);
	char cmd2[]="sh string2.sh";
	system(cmd2);

	char cmd3[]="sh blue_write.sh"
	system(cmd3);
	char cmd4[]="sh green_write.sh"
	system(cmd4);
	char cmd5[]="sh red_write.sh"
	system(cmd5);
	
	fclose(f);
	free(RGB);
}

///void YUV2RGB();
int write_BMP_Header(char *filename,int *h,int *w,BMP *bmp)
{


	FILE *f;
	int *p;
	f=fopen(filename,"w");
	printf("\n Writing BMP Header ");
	fwrite(&bmp->bType,sizeof(unsigned short),1,f);
	p=(int *)bmp;
	fwrite(p+1,sizeof(BMP)-4,1,f);
	return 1;
}


int hexadecimal_to_decimal(int x)
{
	int decimal_number, remainder, count = 0;
	while(x > 0)
	{
		remainder = x % 10;
		decimal_number = decimal_number + remainder * pow(16, count);
		x = x / 10;
		count++;
	}
	return decimal_number;
}


void write_BMP_Data(char *filename,int *h,int *w,BMP *bmp){

	int i,j,i1,H,W,Wp,PAD;
	unsigned char *RGB;
	FILE *f;
	printf("\nWriting BMP Data\n");
	f=fopen(filename,"w");
	fseek(f, 0, SEEK_SET);
	fseek(f, bmp->bOffBits, SEEK_SET);
	W = bmp->bWidth;
	H = bmp->bHeight;
	printf("\nheight = %d width= %d ",H,W);
	PAD = (3 * W) % 4 ? 4 - (3 * W) % 4 : 0;
	Wp = 3 * W + PAD;
	RGB = (unsigned char *)malloc(Wp* H * sizeof(unsigned char));


	FILE **outputfinal=(FILE**)malloc(sizeof(FILE*));
	outputfinal[0]=fopen("blue.txt","r");
	outputfinal[1]=fopen("green.txt","r");
	outputfinal[2]=fopen("red.txt","r");
	if(outputfinal[0]==NULL || outputfinal[1]==NULL || outputfinal[1]==NULL)
	{
		puts("Cannot open output file");
		exit(1);
	}
	//traversing row wise starting from (1,1) to (256,256)
	//string00 blue
	//string11 green
	//string22 red
	i1=0;
	int temp=0;
	for (i = 0; i < H; i++) {
		for (j = 0; j < W; j++){
			i1=i*(Wp)+j*3;
			fscanf(outputfinal[0], "%d",&temp);
			RGB[i1] = hexadecimal_to_decimal(temp);

			fscanf(outputfinal[1], "%d",&temp);
			RGB[i1+1] = hexadecimal_to_decimal(temp);

			fscanf(outputfinal[2], "%d",&temp);
			RGB[i1+2] = hexadecimal_to_decimal(temp);
		}
	}
	fwrite(RGB, sizeof(unsigned char), Wp * H, f);
	fclose(f);
	fclose(outputfinal[0]);
	fclose(outputfinal[1]);
	fclose(outputfinal[2]);
	free(RGB);
}


int main(){

	int PERFORM;
	int h,w;
	BMP b;
	int i,j;
	BMP *bmp=&b;

	Read_BMP_Header("test.bmp",&h,&w,bmp);
	Read_BMP_Data("test.bmp",&h,&w,bmp);


	write_BMP_Header("lowpass.bmp",&h,&w,bmp);
	write_BMP_Data("lowpass.bmp",&h,&w,bmp);
	printf("\n");
	return 0;
}
