#include <stdio.h>
#include <stdlib.h>

//this function prints the values of matrix,each row on a new line
void printMatrix(unsigned short A[16][16]){
	int i,j=0;
	for(i=0;i<16;i++){
		for(j=0;j<16;j++){
			printf("%hu ",A[i][j]);
		}
		printf("\n");
	}
}

void main(){
	unsigned short matrix_element,B[16][16]; 					//declaring temporary variable for matrix element for A and matrixB
	FILE *fp = fopen("matrix_data.txt","r"); 		//opening file which contains data for the 2 matrices
	int i=0,j=0;									//initialising general purpose variables i and j
	FILE *wrt = fopen("writeToBram.sh","w");

//reading data for matrix A	
	fprintf(wrt,"cd C:/makestuff/libs/libfpgalink-20120621\n");
	fprintf(wrt,"./win32/rel/flcli -v 1443:0007 -a \"w0 00;");
	int count=0;	//stores the channel number to which data is to be written
	for(i=0;i<16;i++){
		count++;
		fputs("w",wrt);
		fprintf(wrt,"%02X",count);
		fputs(" ",wrt);
		for(j=0;j<16;j++){
			fscanf(fp,"%hu",&matrix_element);
			fprintf(wrt,"%02X",matrix_element);
		}
		fputs(";",wrt);
	}
//reading data for matrix B 
	count++;
	fputs("w",wrt);
	fprintf(wrt,"%02X",count);
	fputs(" ",wrt);
	for(i=0;i<16;i++){
		for(j=0;j<16;j++){
			fscanf(fp,"%hu",&B[i][j]);
		}
	}
//sending matrix B column-wise
	for(i=0;i<16;i++){
		for(j=0;j<16;j++){
			fprintf(wrt,"%02X",B[j][i]);
		}
	}
	fprintf(wrt,";w0 0102\"");
	fclose(wrt);
	fclose(fp);

//------Reading A and B Complete--------//

//writing A and B to BRAMs
	char cmd[]="sh fpga-link_init.sh";
	system(cmd);
	char cmd1[]="sh writeToBram.sh";
	system(cmd1);

//Checking if C is computed
	unsigned short C[16][16];

	FILE *dc = fopen("dataComputed.sh","w");
	fprintf(dc,"./C:/makestuff/libs/libfpgalink-20120621/win32/rel/flcli -v 1443:0007 -a \"r0 1 \\\"reg0.txt\\\"\"");
	
	char cmd2[]="sh dataComputed.sh";

	unsigned char hex = 0x00;
    while(hex!=0x03){
		system(cmd2);	
    	FILE *fpr0 = fopen("reg0.txt","rb");
   	 	fread ( &hex, 1,1, fpr0);
   	 	fclose(fpr0);
    }
//Read C
    for(i=0;i<16;i++){
		FILE *cr = fopen("Cread.sh","w");
		fprintf(cr,"./C:/makestuff/libs/libfpgalink-20120621/win32/rel/flcli -v 1443:0007 -a \"w0 0103;r%2X 11 \\\"matrix_c.txt\\\"\"",i+18);
		fclose(cr);
		char cmd3[]="sh Cread.sh";
		system(cmd3);	
	    
	    FILE *fpc = fopen("matrix_c.txt","rb");
		unsigned char hex_ar[17] = "";
	   	fread (&hex_ar, 1,17, fpc);
		//skip the first read value
		for(j=0;j<16;j++){
			C[i][j] = (unsigned short)(hex_ar[j+1]);	
		}
	}
	/*
	uint8 buf = 0x00;
	struct FLContext *handle = NULL;
	FLStatus status;
	const char *error = NULL;
	while(buf!=0x03){
		status = flReadChannel(handle, 1000, 0x00, 1, &buf, &error);
	}*/
//Read C
	/*for(i=0;i<16;i++){
		for(j=0;j<16;j++){
			status = flReadChannel(handle, 1000, 0x00, 1, &buf, &error);
			C[i][j] = buf;		
		}
	}*/

//printing C
	 printf("Matrix C:\n");
	 printMatrix(C);
}