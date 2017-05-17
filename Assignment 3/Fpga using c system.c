#include <string.h>
#include <stdio.h>
#include <stdlib.h>

void main(){
	char cmd[]="sh fpga-link_init.sh";
	system(cmd);
	char cmd4[]="sh flcli.sh";
	system(cmd4);
	/*
	char cmd3[]="sh read1.sh";
	system(cmd3);
	char cmd0[]="sh string0.sh";
	system(cmd0);
	char cmd1[]="sh string1.sh";
	system(cmd1);
	char cmd2[]="sh string2.sh";
	system(cmd2);
	system(cmd3);*/
}
