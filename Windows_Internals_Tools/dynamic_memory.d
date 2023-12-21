/* Dynamic Memory DTrace script
 * 
 * This script is used to track the dynamic memory allocation / removal of a Hyper-V VM
 *
 * Written by Andrea Allievi for the Windows Internals Book
 * Last revision: 04th June 2020
 *
 */

#pragma D option quiet

/* Constant values declaration: */
inline int PAGE_SIZE = 4096;
typedef int NTSTATUS;
inline uint32_t STATUS_SUCCESS = 0;

/* Global variables */
int64_t PagesDelta;

BEGIN 
{
    printf("The Dynamic Memory script has begun.\r\n\r\n");
    PagesDelta = 0;
}

fbt:nt:MmAddPhysicalMemory:entry
{
    self->pStartingAddress = (uint64_t*)arg0;
    self->pNumberOfBytes = (uint64_t*)arg1;
    this->StartingPage = (*self->pStartingAddress)  / PAGE_SIZE;
    this->NumberOfPages = (*self->pNumberOfBytes) / PAGE_SIZE;
    
    printf("Physical memory addition request intercepted. Start physical address 0x%08X, Number of pages: 0x%08X.\r\n",
           this->StartingPage, this->NumberOfPages);
}

fbt:nt:MmAddPhysicalMemory:return
/ self->pStartingAddress != 0 /
{
    this->StartingPage = (*self->pStartingAddress) / PAGE_SIZE;
    this->NumberOfPages = (*self->pNumberOfBytes) / PAGE_SIZE;

    if (((NTSTATUS)arg1) == STATUS_SUCCESS) {
        printf("   Addition of %d memory pages starting at PFN 0x%08X succeeded!\r\n",
               this->NumberOfPages, this->StartingPage);

        /* Update the call statistics */    
        @Funcs["Numbers of Hot Additions"] = count();
        PagesDelta += this->NumberOfPages;

    } else {
        printf("   Addition of %d memory pages starting at PFN 0x%08X failed with status 0x%08X.\r\n",
               this->NumberOfPages, this->StartingPage, (NTSTATUS)arg1);
    }
    printf("\r\n");
    
    /* Zero out the saved starting address and number of bytes */
    self->pStartingAddress = 0;
    self->pNumberOfBytes = 0;
}

fbt:nt:MiRemovePhysicalMemory:entry
{
    self->StartPage = (uint64_t)arg0;
    self->NumberOfPages = (uint64_t)arg1;
    
    printf("Physical memory removal request intercepted. Start physical address 0x%08X, Number of pages: 0x%08X.\r\n",
           self->StartPage, self->NumberOfPages);
}

fbt:nt:MiRemovePhysicalMemory:return
/ self->StartPage != 0 /
{
    if ((NTSTATUS)arg1 == STATUS_SUCCESS) {
        printf("   Removal of %d memory pages starting at PFN 0x%08X succeeded!\r\n",
               self->NumberOfPages, self->StartPage);

        /* Update the call statistics */    
        @Funcs["Numbers of Hot Removals"] = count();
        PagesDelta -= self->NumberOfPages;

    } else {
        printf("   Removal of %d memory pages starting at PFN 0x%08X failed with status 0x%08X.\r\n",
               self->NumberOfPages, self->StartPage, (NTSTATUS)arg1);
    }
    printf("\r\n");

    /* Zero out the saved starting page and total number of pages */
    self->StartPage = 0;
    self->NumberOfPages = 0;
}

END 
{
    printf("Dynamic Memory script ended.\r\n");

    printa("%s: %@i\n", @Funcs);
    if (PagesDelta >= 0) {
       this->Op = "gained";
    } else {
       this->Op = "lost";
       PagesDelta = (-PagesDelta)
    }
    printf("Since starts the system has %s 0x%08X pages (%i MB).\n",
           this->Op, PagesDelta, (PagesDelta * PAGE_SIZE) / (1024 * 1024));
}



