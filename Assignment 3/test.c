
#include <string.h>
#include <stdio.h>
#include <math.h>
#include <stdlib.h>

void main(){
	FILE **outputfinal=(FILE**)malloc(sizeof(FILE*));
	
	FILE *fp=fopen("C:\\makestuff\\libs\\libfpgalink-20120621\\blue_write.txt","rb");
	
	unsigned char hex[1024] = "";
    int each = 0;
    size_t bytes = 0;
    
    while ( ( bytes = fread ( &hex, 1, 1024, fp)) > 0) {
        for ( each = 0; each < bytes; each++) {
            printf ( "read this char as int %u and as hex %x\n", hex[each], hex[each]);
        }
    }
    fclose ( fp);


}