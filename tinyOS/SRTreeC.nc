#include "SimpleRoutingTree.h"
//new inclusions
#include <stdio.h>  
#include <stdlib.h>
#include <time.h>
#ifdef PRINTFDBG_MODE
	#include "printf.h"
#endif
//This is The Main branch.
module SRTreeC
{
	uses interface Boot;
	

	//used for starting comunication components and cheching ex if they started etc
	/*example:
	  arxikopoiisi radio kai serial
		call RadioControl.start();
	example:
	  check if the radio started succesfully
	  example:event void RadioControl.startDone(error_t err)
	{
		if (err == SUCCESS)
		{....*/

	uses interface SplitControl as RadioControl;
	//used for starting comunication components and cheching ex if they started etc	

	//used for communicating routing packets
	uses interface Packet as RoutingPacket;
	uses interface AMSend as RoutingAMSend;
	uses interface AMPacket as RoutingAMPacket;
	//used for communicating measurement packets
	uses interface Packet as MeasurementPacket;
	uses interface AMSend as MeasurementAMSend;
	uses interface AMPacket as MeasurementAMPacket;

	

	
	//Routing Timer, starts from node zero and propagates down the line 
	uses interface Timer<TMilli> as RoutingMsgTimer;
	//Data transmition timer, fires once its time for a specific node to send data
	uses interface Timer<TMilli> as SendMeasurementTimer;
	//routing done timer, fires once in the whole proccess, it signifies the end of the routing phase 
	uses interface Timer<TMilli> as RoutingFinishedTimer;

	// Use random interface to generate random numbers.
	uses interface Random as RandomMeasurement;
	uses interface ParameterInit<uint16_t> as Seed;

	//probably for part 2
	uses interface Timer<TMilli> as LostTaskTimer;
	
	//interface responsible for receiving data
	//receive for routing
	uses interface Receive as RoutingReceive;
	//receive for measurements
	uses interface Receive as MeasurementReceive;
	
	
	//Packet queue implementations
	//routing packet queues
	uses interface PacketQueue as RoutingSendQueue;
	uses interface PacketQueue as RoutingReceiveQueue;
	// Measurement packet queues
	uses interface PacketQueue as MeasurementSendQueue;
	uses interface PacketQueue as MeasurementReceiveQueue;
	
	
}
implementation
{
	//counts the number of rounds passed
	uint16_t  roundCounter;
	
	message_t radioRoutingSendPkt;
	message_t radioMeasurementSendPkt;
	
	
	
	
	//Busy flags
	bool RoutingSendBusy=FALSE;
	bool MeasurementSendBusy=FALSE;

	//part 2
	bool lostRoutingSendTask=FALSE;	
	bool lostRoutingRecTask=FALSE;

	bool lostMeasurementSendTask=FALSE;	
	bool lostMeasurementRecTask=FALSE;
	
	
	// BASE NODE VARIABLES
	uint8_t curdepth;
	uint16_t parentID;
	//ADDITIONAL ADDED NODE VARIABLES
	//the new measurement for this epoch
	uint16_t measurement=-1;
	//stores old measurement to calculate +-20% of the old measurement
	uint16_t old_measurement=-1;

	//holds sum of all measurements passed through
	//one for each different group
	uint16_t aggregate_measurement=0;
	uint16_t aggregate_measurement1=0;
	uint16_t aggregate_measurement2=0;

	// a 8 bit number of which only the last 3 bits matter
	//it is encoded in a way so that each of the last 3 bits corresponds to a different group
	//if a bit is 1 means that this node or one+ of its children belong to this group
	//it is used to determine the size of the message sent
	uint8_t includedGroups = 0;
	//when it receives a message, the included groups value is stored temporarily here
	uint8_t receiveIncludedGroups = 0;

	//holds sum of the number of all nodes passed through 
	//one for each different group
	uint8_t count=0;
	uint8_t count1=0;
	uint8_t count2=0;

	//random number that determines which groups exist
	uint8_t RANDOM_NUM=0;  
	//stores the group number that this node belongs  
	uint8_t group=0;     

	uint8_t groupsCounter=0;

	//used to import a seed to improve the randomness
	FILE *filePointer;
	uint16_t seed;
	

	//BASE FUCTIONS FOR NODE INTERACTIONS	
	task void sendRoutingTask();	
	task void receiveRoutingTask();

	task void sendMeasurementTask();	
	task void receiveMeasurementTask();

	//creates the measurement message to be sent
	task void RandNumMaker();


	//Part 2 maybe
	void setLostRoutingSendTask(bool state)
	{
		atomic{
			lostRoutingSendTask=state;
		}		
	}
	void setLostMeasurementSendTask(bool state)
	{
		atomic{
			lostMeasurementSendTask=state;
		}		
	}
	
	
	//Part 2 maybe
	void setLostRoutingRecTask(bool state)
	{
		atomic{
		lostRoutingRecTask=state;
		}
	}
	void setLostMeasurementRecTask(bool state)
	{
		atomic{
		lostMeasurementRecTask=state;
		}
	}


	//Change node radio busy state to avoid data loss
	void setRoutingSendBusy(bool state)
	{
		atomic{
		RoutingSendBusy=state;
		}	
		
	}

	// New function for Measurement Send boolean state 
	void setMeasurementSendBusy(bool state)
	{
		atomic{
		MeasurementSendBusy=state;
		}	
		
	}
	
	

////////////////////////////////////////////////////////////////
// ACTUAL CODE STARTS HERE
////////////////////////////////////////////////////////////////
	event void Boot.booted()
	{
		/////// arxikopoiisi radio 
		//radio start
		//it takes some time that sould be acounted for
		call RadioControl.start();
		
		//node radio not busy
		setRoutingSendBusy(FALSE);

		// measurement send not busy at first
		setMeasurementSendBusy(FALSE);
		

		//initialize round counter
		roundCounter =0;		
		//if node is base node then initialize the groups and initiate routing 
		if(TOS_NODE_ID==0)
		{
			//if node is the BASE NODE
			//initialize NODE VARIABLES
			curdepth=0;
			parentID=0;			
			srand ( time(NULL) );
			filePointer = fopen("/dev/urandom", "r");
			fread(&seed, sizeof(seed), 1, filePointer);
			fclose(filePointer);
			call Seed.init(seed + TOS_NODE_ID + 1);
			RANDOM_NUM=(uint8_t)(call RandomMeasurement.rand16() % 3)+1;			
			dbg("final" , "RANDOM_NUM : %u \n", RANDOM_NUM);
			//debug
			dbg("Boot", "curdepth = %d  ,  parentID= %d \n", curdepth , parentID);
#ifdef PRINTFDBG_MODE
			printf("Booted NodeID= %d : curdepth= %d , parentID= %d \n", TOS_NODE_ID ,curdepth , parentID);
			printfflush();
#endif
		}
		else
		{
			//if node is not the base node
			//initialize NODE VARIABLES
			curdepth=-1;
			parentID=-1;

			//debug
			dbg("Boot", "curdepth = %d  ,  parentID= %d \n", curdepth , parentID);
#ifdef PRINTFDBG_MODE
			printf("Booted NodeID= %d : curdepth= %d , parentID= %d \n", TOS_NODE_ID ,curdepth , parentID);
			printfflush();
#endif
		}
	}


////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
//RADIO  START STOP
////////////////////////////////////////////////////////////////////////////////////////////////
	//first function to be called after boot is complete
	event void RadioControl.startDone(error_t err)
	{
		//Radio initialized successfully
		if (err == SUCCESS)
		{
			dbg("Radio" , "Radio initialized successfully!!!\n");
#ifdef PRINTFDBG_MODE
			printf("Radio initialized successfully!!!\n");
			printfflush();
#endif

			//when this timer fires, routing should have finished
			call RoutingFinishedTimer.startOneShot(90*1024);
			if (TOS_NODE_ID==0)
			{

				// EPOCH START
				//TIMER startOneShot():a timer that fires once after a specified duration
				//Fires one time after TIMER_FAST_PERIOD eg. 512ms == 0.5 sec
				//we want it to fire after every node has booted up				
				call RoutingMsgTimer.startOneShot(TIMER_FAST_PERIOD);
				
				// EPOCH START
			}
		}
		else
		{
			dbg("Radio" , "Radio initialization failed! Retrying...\n");
#ifdef PRINTFDBG_MODE
			printf("Radio initialization failed! Retrying...\n");
			printfflush();
#endif
			//retry starting radio
			call RadioControl.start();
		}
	}
	//stop radio
	event void RadioControl.stopDone(error_t err)
	{ 
		dbg("Radio", "Radio stopped!\n");
#ifdef PRINTFDBG_MODE
		printf("Radio stopped!\n");
		printfflush();
#endif
	}	
	
	////////////////////////////////////////////////////////////////////////
	///// TIMER FIRED////////////////////////////////
	////////////////////////////////////////////////////////////////////////

	//part 2
	event void LostTaskTimer.fired()
	{
		if (lostRoutingSendTask)
		{
			post sendRoutingTask();
			setLostRoutingSendTask(FALSE);
		}
		
		
		
		if (lostRoutingRecTask)
		{
			post receiveRoutingTask();
			setLostRoutingRecTask(FALSE);
		}

		if (lostMeasurementSendTask)
		{
			post sendMeasurementTask();
			setLostMeasurementSendTask(FALSE);
		}
		
		
		
		if (lostMeasurementRecTask)
		{
			post receiveMeasurementTask();
			setLostMeasurementRecTask(FALSE);
		}
		
		
	}
	
	//define when each node will fire depending on its depth
	//added randomness for collision avoidance
	event void RoutingFinishedTimer.fired(){
		roundCounter=0;
		call SendMeasurementTimer.startPeriodicAt((-curdepth*TIMER_FAST_SEND_MEASUREMENT_PERIOD+(call RandomMeasurement.rand16() % (TIMER_FAST_SEND_MEASUREMENT_PERIOD/2))),TIMER_PERIOD_MILLI);

	}
	//time to send measurement message
	event void SendMeasurementTimer.fired()
	{
		//create a measurement message to send
		post RandNumMaker();		
	}

	//Routing timer fired
	event void RoutingMsgTimer.fired()
	{
		message_t tmp;
		error_t enqueueDone;
		
		RoutingMsg* mrpkt;
		dbg("SRTreeC", "RoutingMsgTimer fired!  radioBusy = %s \n",(RoutingSendBusy)?"True":"False");
#ifdef PRINTFDBG_MODE
		printfflush();
		printf("RoutingMsgTimer fired!  radioBusy = %s \n",(RoutingSendBusy)?"True":"False");
		printfflush();
#endif
		if (TOS_NODE_ID==0)
		{
			roundCounter+=1;
			
			dbg("SRTreeC", "\n ##################################### \n");
			dbg("SRTreeC", "#######   Routing     ############## \n");
			dbg("SRTreeC", "#####################################\n");
			
			//call RoutingMsgTimer.startOneShot(TIMER_PERIOD_MILLI);
		}
		
		if(call RoutingSendQueue.full())
		{
#ifdef PRINTFDBG_MODE
			printf("RoutingSendQueue is FULL!!! \n");
			printfflush();
#endif
			return;
		}
		
		
		mrpkt = (RoutingMsg*) (call RoutingPacket.getPayload(&tmp, sizeof(RoutingMsg)));
		if(mrpkt==NULL)
		{
			dbg("SRTreeC","RoutingMsgTimer.fired(): No valid payload... \n");
#ifdef PRINTFDBG_MODE
			printf("RoutingMsgTimer.fired(): No valid payload... \n");
			printfflush();
#endif
			return;
		}
		//atomic is to avoid interuptions
		atomic{
		mrpkt->senderID=TOS_NODE_ID;
		mrpkt->depth = curdepth;
		mrpkt->RANDOM_NUM=RANDOM_NUM;
		}
		dbg("SRTreeC" , "Sending RoutingMsg... \n");

#ifdef PRINTFDBG_MODE
		printf("NodeID= %d : RoutingMsg sending...!!!! \n", TOS_NODE_ID);
		printfflush();
#endif	
		//AM_BROADCAST_ADDR sends a broadcast, instead we can enter a specific ID	
		//broadcast that youre an available father
		call RoutingAMPacket.setDestination(&tmp, AM_BROADCAST_ADDR);
		call RoutingPacket.setPayloadLength(&tmp, sizeof(RoutingMsg));
		//add broadcast to send queue
		enqueueDone=call RoutingSendQueue.enqueue(tmp);
		
		//added to send queue successfully
		if( enqueueDone==SUCCESS)
		{
			if (call RoutingSendQueue.size()==1)
			{
				dbg("SRTreeC", "SendTask() posted!!\n");
#ifdef PRINTFDBG_MODE
				printf("SendTask() posted!!\n");
				printfflush();
#endif
				post sendRoutingTask();
			}
			
			dbg("SRTreeC","RoutingMsg enqueued successfully in SendingQueue!!!\n");
#ifdef PRINTFDBG_MODE
			printf("RoutingMsg enqueued successfully in SendingQueue!!!\n");
			printfflush();
#endif
		}
		else
		{
			dbg("SRTreeC","RoutingMsg failed to be enqueued in SendingQueue!!!");
#ifdef PRINTFDBG_MODE			
			printf("RoutingMsg failed to be enqueued in SendingQueue!!!\n");
			printfflush();
#endif
		}		
	}
	
	

	////////////////////////////////////////////////////////////////
	// WHEN A MESSAGE IS SENT AND WE WANNA CHECK IF ITS DONE SUCCESSFULY TO MAKE UNBUSY
	////////////////////////////////////////////////////////////////// 
	event void RoutingAMSend.sendDone(message_t * msg , error_t err)
	{
		dbg("SRTreeC", "A Routing package sent... %s \n",(err==SUCCESS)?"True":"False");
#ifdef PRINTFDBG_MODE
		printf("A Routing package sent... %s \n",(err==SUCCESS)?"True":"False");
		printfflush();
#endif
		
		dbg("SRTreeC" , "Package sent %s \n", (err==SUCCESS)?"True":"False");
#ifdef PRINTFDBG_MODE
		printf("Package sent %s \n", (err==SUCCESS)?"True":"False");
		printfflush();
#endif
		setRoutingSendBusy(FALSE);
		
		if(!(call RoutingSendQueue.empty()))
		{
			post sendRoutingTask();
		}	
	}
	event void MeasurementAMSend.sendDone(message_t * msg , error_t err)
	{
		dbg("SRTreeC", "A Measurement package sent... %s \n",(err==SUCCESS)?"True":"False");
#ifdef PRINTFDBG_MODE
		printf("A Measurement package sent... %s \n",(err==SUCCESS)?"True":"False");
		printfflush();
#endif
		
		dbg("SRTreeC" , "Package sent %s \n", (err==SUCCESS)?"True":"False");
#ifdef PRINTFDBG_MODE
		printf("Package sent %s \n", (err==SUCCESS)?"True":"False");
		printfflush();
#endif
		setMeasurementSendBusy(FALSE);
		
		if(!(call MeasurementSendQueue.empty()))
		{
			post sendMeasurementTask(); 
		}	
	}
	

		
	////////////////////////////////////////////////////////////////////////////////////////////////
	// RECIEVE FUNCTIONS //////////////////////////////////
	////////////////////////////////////////////////////////////////////////////////////////////////

//	event message_t* Receive.receive(message_t* msg, void* payload, uint8_t len)
	event message_t* RoutingReceive.receive( message_t * msg , void * payload, uint8_t len)
	{
		error_t enqueueDone;
		message_t tmp;
		uint16_t msource;
		
		msource =call RoutingAMPacket.source(msg);
		
		dbg("SRTreeC", "### RoutingReceive.receive() start ##### \n");
		dbg("SRTreeC", "Something received!!!  from %u  %u \n",((RoutingMsg*) payload)->senderID ,  msource);
		//dbg("SRTreeC", "Something received!!!\n");
#ifdef PRINTFDBG_MODE		
		printf("Something Received!!!, len = %u , rm=%u\n",len, sizeof(RoutingMsg));
		printfflush();
#endif
		
		
		atomic{
		memcpy(&tmp,msg,sizeof(message_t));
		//tmp=*(message_t*)msg;
		}
		// add to receive message queue to proccess
		enqueueDone=call RoutingReceiveQueue.enqueue(tmp);
		if(enqueueDone == SUCCESS)
		{
#ifdef PRINTFDBG_MODE
			printf("posting receiveRoutingTask()!!!! \n");
			printfflush();
#endif
			post receiveRoutingTask();
		}
		else
		{
			dbg("SRTreeC","RoutingMsg enqueue failed!!! \n");
#ifdef PRINTFDBG_MODE
			printf("RoutingMsg enqueue failed!!! \n");
			printfflush();
#endif			
		}		
		dbg("SRTreeC", "### RoutingReceive.receive() end ##### \n");
		return msg;
	}
	//received a measurement message
	event message_t* MeasurementReceive.receive( message_t * msg , void * payload, uint8_t len)
	{
		error_t enqueueDone;
		message_t tmp;
		uint16_t msource;
		
		msource =call MeasurementAMPacket.source(msg);
		
		dbg("comm", "### MeasurementReceive.receive() start ##### \n");
		dbg("comm", "Something received!!!  from %u  %u \n",((MeasurementMsg*) payload)->count ,  measurement);
		//dbg("SRTreeC", "Something received!!!\n");
#ifdef PRINTFDBG_MODE		
		printf("Something Received!!!, len = %u , rm=%u\n",len, sizeof(MeasurementMsg));
		printfflush();
#endif
		
		
		atomic{
		memcpy(&tmp,msg,sizeof(message_t));
		//tmp=*(message_t*)msg;
		}
		enqueueDone=call MeasurementReceiveQueue.enqueue(tmp);
		if(enqueueDone == SUCCESS)
		{
#ifdef PRINTFDBG_MODE
			printf("posting receiveMeasurementTask()!!!! \n");
			printfflush();
#endif		// proccess received message
			post receiveMeasurementTask(); 
		}
		else
		{
			dbg("comm","MeasurementMsg enqueue failed!!! \n");
#ifdef PRINTFDBG_MODE
			printf("MeasurementMsg enqueue failed!!! \n");
			printfflush();
#endif			
		}		
		dbg("comm", "### MeasurementReceive.receive() end ##### \n");
		return msg;
	}
	

	////////////// Tasks implementations //////////////////////////////
	

	////////////////////////////////////////////////////////////////////////////////////////////////
	// BASICALLY SEND AND RECIEVE FOR ROUTING AND NOTIFY
	////////////////////////////////////////////////////////////////
	// SEND TAKES FROM BUFFER OF MESSAGES TO SEND AND IF THERE ARE NO COMPLICATIONS
	// DEQUEUES THE MESSAGE AND SENDS USING THE APPROPRIATE SEND FUNCTION 
	////////////////////////////////////////////////////////////////////////
	// RECIEVE TAKES MESSAGE FROM 'INBOX' BUFFER AND PROSSESES IT
	////////////////////////////////////////////////////////////////////////////
	task void RandNumMaker(){
		message_t tmp;
		error_t enqueueDone;
		//pointers to the 3 different types of messages that can be received
		MeasurementMsg* mrpkt;
		MeasurementMsg1* mrpkt1;
		MeasurementMsg2* mrpkt2;
		
		dbg("comm", "SendMeasurementTimer fired!  radioBusy = %s , this node depth is: %d \n",(MeasurementSendBusy ? "True" : "False"),curdepth);
#ifdef PRINTFDBG_MODE
		printfflush();
		printf("SendMeasurementTimer fired!  radioBusy = %s \n",(MeasurementSendBusy)?"True":"False");
		printfflush();
#endif
		
		
		

		// Check if queue is full
		if(call MeasurementSendQueue.full())
		{
#ifdef PRINTFDBG_MODE
			printf("MeasurementSendQueue is FULL!!! \n");
			printfflush();
#endif
			return;
		}	
		
		//add this nodes data to the appropriate group aggregate
		if(group==0){
			count+=1;
			aggregate_measurement+=measurement;

		}else if(group==1){
			count1+=1;
			aggregate_measurement1+=measurement;
		}else{
			count2+=1;
			aggregate_measurement2+=measurement;
		}
		//set which groups are present 
		groupsCounter=0;
		//if the aggregate_measurement is 0 means that no nodes of this group have passed through
		if (aggregate_measurement != 0) { //if nodes from group 0 have passed through
			includedGroups |= (1 << 0);  // Set the first bit to 1
			groupsCounter+=1;
		}

		if (aggregate_measurement1 != 0) {//if nodes from group 1 have passed through
			includedGroups |= (1 << 1);  // Set the second bit to 1
			groupsCounter+=1;
		}

		if (aggregate_measurement2 != 0) {//if nodes from group 2 have passed through
			includedGroups |= (1 << 2);  // Set the third bit to 1
			groupsCounter+=1;
		}
		//keep old measurement 
		old_measurement=measurement;
		//create random measurement
		if(measurement==-1){
			measurement = (call RandomMeasurement.rand16() % 100);			
			old_measurement=measurement;
		}
		else {
			//+-20% of old measurement
			uint8_t upperBound = (int)old_measurement + 0.2*old_measurement;
			uint8_t lowerBound = (int)old_measurement - 0.2*old_measurement;

			measurement = call RandomMeasurement.rand16()%(upperBound-lowerBound) + lowerBound;
		
			//check so that the node doesnt pass the value bounds
			if(measurement<1){
				measurement=1;
			}
			if(measurement>100){
				measurement=100;
			}
			old_measurement=measurement;
		}
		dbg("measurements", "####### Node:%d created measurement  %d     ############## \n",TOS_NODE_ID,measurement);
		
		//DECIDE MESSAGE SIZE DEPENDING ON THE NUMBER OF DIFFERENT GROUPS INCLUDED
		//if one group present
		if(groupsCounter==1){
			
			//create measurement message			
			call MeasurementPacket.setPayloadLength(&tmp, sizeof(MeasurementMsg));
			mrpkt = (MeasurementMsg*) (call MeasurementPacket.getPayload(&tmp, sizeof(MeasurementMsg)));
			
			if(mrpkt==NULL)
			{
				dbg("comm","MeasurementMsgTimer.fired(): No valid payload... \n");
	#ifdef PRINTFDBG_MODE
				printf("MeasurementMsgTimer.fired(): No valid payload... \n");
				printfflush();
	#endif
				return;
			}
			atomic{
				//destination to parents 
				call MeasurementAMPacket.setDestination(&tmp, parentID);
				mrpkt->includedGroups=includedGroups;
			}
			//check nodes of which group exist
				if (aggregate_measurement != 0) {
					atomic{
					mrpkt->count=count;
					mrpkt->measurement = aggregate_measurement;}
				}else if (aggregate_measurement1!=0) {
					atomic{
					mrpkt->count=count1;
					mrpkt->measurement = aggregate_measurement1;}

				}else{
					atomic{
					mrpkt->count=count2;
					mrpkt->measurement = aggregate_measurement2;}

				}
		//if 2 groups present 	
		}else if(groupsCounter==2){
			
			//create measurement messagge			
			call MeasurementPacket.setPayloadLength(&tmp, sizeof(MeasurementMsg1));
			mrpkt1 = (MeasurementMsg1*) (call MeasurementPacket.getPayload(&tmp, sizeof(MeasurementMsg1)));
			
				if(mrpkt1==NULL)
				{
					dbg("comm","MeasurementMsgTimer.fired(): No valid payload... \n");
		#ifdef PRINTFDBG_MODE
					printf("MeasurementMsgTimer.fired(): No valid payload... \n");
					printfflush();
		#endif
					return;
				}
			atomic{//decide which data is stored to which message variable 
					//in a way that can be read correctly afterwards
				call MeasurementAMPacket.setDestination(&tmp, parentID);
				mrpkt1->includedGroups=includedGroups;}
				if (aggregate_measurement == 0) {
					atomic{
					mrpkt1->count = count1;
					mrpkt1->measurement = aggregate_measurement1;
					mrpkt1->count1 = count2;
					mrpkt1->measurement1 = aggregate_measurement2;}

				} else if (aggregate_measurement1 == 0) {
					atomic{
					mrpkt1->count = count;
					mrpkt1->measurement = aggregate_measurement;
					mrpkt1->count1 = count2;
					mrpkt1->measurement1 = aggregate_measurement2;}
				}else {
					atomic{
					mrpkt1->count = count;
					mrpkt1->measurement = aggregate_measurement;
					mrpkt1->count1 = count1;
					mrpkt1->measurement1 = aggregate_measurement1;}
				}

			
			

		}else{//3 groups present
			
			//create measurement messagge			
			call MeasurementPacket.setPayloadLength(&tmp, sizeof(MeasurementMsg2));
			mrpkt2 = (MeasurementMsg2*) (call MeasurementPacket.getPayload(&tmp, sizeof(MeasurementMsg2)));
			
				if(mrpkt2==NULL)
				{
					dbg("comm","MeasurementMsgTimer.fired(): No valid payload... \n");
		#ifdef PRINTFDBG_MODE
					printf("MeasurementMsgTimer.fired(): No valid payload... \n");
					printfflush();
		#endif
					return;
				}
			atomic{	
			call MeasurementAMPacket.setDestination(&tmp, parentID);
			mrpkt2->includedGroups=includedGroups;
			mrpkt2->count = count;
			mrpkt2->measurement = aggregate_measurement;
			mrpkt2->count1 = count1;
			mrpkt2->measurement1 = aggregate_measurement1;
			mrpkt2->count2 = count2;
			mrpkt2->measurement2 = aggregate_measurement2;}
		}
		
		dbg("comm" , "Sending MeasurementMsg... \n");
dbg("final","children belong to %d different groups\n",groupsCounter);
//dbg("final","message sizes:%d , %d, %d\n",sizeof(MeasurementMsg),sizeof(MeasurementMsg1),sizeof(MeasurementMsg2));
#ifdef PRINTFDBG_MODE
		printf("NodeID= %d : MeasurementMsg sending...!!!! \n", TOS_NODE_ID);
		printfflush();
#endif	
	
			//select father as receiver
		
		
		enqueueDone=call MeasurementSendQueue.enqueue(tmp);
		//reset measurement values
		
		
		if( enqueueDone==SUCCESS)
		{
			if (call MeasurementSendQueue.size()==1)
			{
				//dbg("final", "SendTask() posted!!\n");
#ifdef PRINTFDBG_MODE
				printf("SendTask() posted!!\n");
				printfflush();
#endif
				post sendMeasurementTask(); 
			}
			
			dbg("comm","MeasurementMsg enqueued successfully in SendingQueue!!!\n");
#ifdef PRINTFDBG_MODE
			printf("MeasurementMsg enqueued successfully in SendingQueue!!!\n");
			printfflush();
#endif
		}
		else
		{
			dbg("comm","MeasurementMsg failed to be enqueued in SendingQueue!!!");
#ifdef PRINTFDBG_MODE			
			printf("MeasurementMsg failed to be enqueued in SendingQueue!!!\n");
			printfflush();
#endif
		}	

	}
				
	task void sendMeasurementTask(){
		//uint8_t skip;
		uint8_t mlen;
		uint16_t mdest;
		error_t sendDone;
		//message_t radioRoutingSendPkt;
		dbg("final" , "Node results :count= %d , aggregate= %d , node depth: %d , group:%d , parent ID:%d\n", count , aggregate_measurement,curdepth,group,parentID);
		dbg("final" , "Node results :count1= %d , aggregate1= %d , node depth: %d , group:%d , parent ID:%d\n", count1 , aggregate_measurement1,curdepth,group,parentID);
		dbg("final" , "Node results :count2= %d , aggregate2= %d , node depth: %d , group:%d , parent ID:%d\n\n", count2 , aggregate_measurement2,curdepth,group,parentID);
		//to avoid division errors
		if(TOS_NODE_ID==0){
			if(count==0){
				count=1;
			}
			if(count1==0){
				count1=1;
			}
			if(count2==0){
				count2=1;
			}
			dbg("final" , "FINAL RESULT group 1: %u \n", aggregate_measurement/count);
			dbg("final" , "FINAL RESULT group 2: %u \n", aggregate_measurement1/count1);
			dbg("final" , "FINAL RESULT group 3: %u\n", aggregate_measurement2/count2);
			
		
		}
		///the next lines throw segmantation error
		count=0;
		aggregate_measurement=0;
		count1=0;
		aggregate_measurement1=0;
		count2=0;
		aggregate_measurement2=0;
		
	
		if(TOS_NODE_ID==0){// a new epoch starts here
			dbg("final", "##################################### \n");
			dbg("final", "##########   Epoch %d     ########### \n", roundCounter);
			dbg("final", "#####################################\n");
			roundCounter+=1;
		}
		
#ifdef PRINTFDBG_MODE
		printf("SendMeasurementTask(): Starting....\n");
		printfflush();
#endif
		if (call MeasurementSendQueue.empty())
		{
			dbg("comm","sendMeasurementTask(): Q is empty!\n");
#ifdef PRINTFDBG_MODE		
			printf("sendMeasurementTask():Q is empty!\n");
			printfflush();
#endif
			return;
		}
		
		
		if(MeasurementSendBusy)
		{
			dbg("comm","sendMeasurementTask(): MeasurementSendBusy= TRUE!!!\n");
#ifdef PRINTFDBG_MODE
			printf(	"sendMeasurementTask(): MeasurementSendBusy= TRUE!!!\n");
			printfflush();
#endif
			setLostMeasurementSendTask(TRUE);
			return;
		}
		
		radioMeasurementSendPkt = call MeasurementSendQueue.dequeue();		
		
		mlen= call MeasurementPacket.payloadLength(&radioMeasurementSendPkt);
		mdest=call MeasurementAMPacket.destination(&radioMeasurementSendPkt);
		
		sendDone=call MeasurementAMSend.send(mdest,&radioMeasurementSendPkt,mlen);
		dbg("final","...\n");
		dbg("final","...\n");
		dbg("final","...\n");
		dbg("final","...\n");
		dbg("final","...\n");

		dbg("final","SENDING MESSAGE OF LENGHT:%d\n",mlen);
		
		if ( sendDone== SUCCESS)
		{
			dbg("final","Message succesfully sent\n");
#ifdef PRINTFDBG_MODE
			printf("sendMeasurementTask(): Send returned success!!!\n");
			printfflush();
#endif
			setMeasurementSendBusy(TRUE);
		}
		else
		{
			dbg("final","send failed!!!\n");
#ifdef PRINTFDBG_MODE
			printf("SendMeasurementTask(): send failed!!!\n");
#endif
			//setMeasurementSendBusy(FALSE);
		}

	}
	
	task void sendRoutingTask()
	{
		//uint8_t skip;
		uint8_t mlen;
		uint16_t mdest;
		error_t sendDone;
		//message_t radioRoutingSendPkt;
		
#ifdef PRINTFDBG_MODE
		printf("SendRoutingTask(): Starting....\n");
		printfflush();
#endif
		if (call RoutingSendQueue.empty())
		{
			dbg("SRTreeC","sendRoutingTask(): Q is empty!\n");
#ifdef PRINTFDBG_MODE		
			printf("sendRoutingTask():Q is empty!\n");
			printfflush();
#endif
			return;
		}
		
		
		if(RoutingSendBusy)
		{
			dbg("SRTreeC","sendRoutingTask(): RoutingSendBusy= TRUE!!!\n");
#ifdef PRINTFDBG_MODE
			printf(	"sendRoutingTask(): RoutingSendBusy= TRUE!!!\n");
			printfflush();
#endif
			setLostRoutingSendTask(TRUE);
			return;
		}
		
		radioRoutingSendPkt = call RoutingSendQueue.dequeue();
		
		mlen= call RoutingPacket.payloadLength(&radioRoutingSendPkt);
		mdest=call RoutingAMPacket.destination(&radioRoutingSendPkt);
		if(mlen!=sizeof(RoutingMsg))
		{
			dbg("SRTreeC","\t\tsendRoutingTask(): Unknown message!!!\n");
#ifdef PRINTFDBG_MODE
			printf("\t\tsendRoutingTask(): Unknown message!!!!\n");
			printfflush();
#endif
			return;
		}
		sendDone=call RoutingAMSend.send(mdest,&radioRoutingSendPkt,mlen);
		
		if ( sendDone== SUCCESS)
		{
			dbg("SRTreeC","sendRoutingTask(): Send returned success!!!\n");
#ifdef PRINTFDBG_MODE
			printf("sendRoutingTask(): Send returned success!!!\n");
			printfflush();
#endif
			setRoutingSendBusy(TRUE);
		}
		else
		{
			dbg("SRTreeC","send failed!!!\n");
#ifdef PRINTFDBG_MODE
			printf("SendRoutingTask(): send failed!!!\n");
#endif
			//setRoutingSendBusy(FALSE);
		}
	}

	////////////////////////////////////////////////////////////////////
	//*****************************************************************/
	///////////////////////////////////////////////////////////////////
	/**
	 * dequeues a message and processes it
	 */

	task void receiveMeasurementTask(){
		message_t tmp;
		uint8_t len;
		message_t radioMeasurementRecPkt;
		MeasurementMsg* mpkt0;
		MeasurementMsg1* mpkt1;
		MeasurementMsg2* mpkt2;
#ifdef PRINTFDBG_MODE
		printf("ReceiveMeasurementTask():received msg...\n");
		printfflush();
#endif
		radioMeasurementRecPkt= call MeasurementReceiveQueue.dequeue();
		
		len= call MeasurementPacket.payloadLength(&radioMeasurementRecPkt);
		
		dbg("final","ReceiveMeasurementTask(): len=%u \n",len);
#ifdef PRINTFDBG_MODE
		printf("ReceiveMeasurementTask(): len=%u!\n",len);
		printfflush();
#endif
		// processing of measurement packet
		//if message has 1 group of nodes		
		if(len == sizeof(MeasurementMsg))
		{
			mpkt0 = (MeasurementMsg*) (call MeasurementPacket.getPayload(&radioMeasurementRecPkt,len));
			dbg("final","received group0\n");	
			
			atomic{//decode includedGroups to find out the included group
			//and add measurements to local variables
			receiveIncludedGroups=mpkt0->includedGroups;}
			if ((receiveIncludedGroups & 0b001) == 0b001){
				atomic{
				aggregate_measurement+=mpkt0->measurement;
				count+=mpkt0->count;}
				
			} else if((receiveIncludedGroups & 0b010) == 0b010){
				atomic{
				aggregate_measurement1+=mpkt0->measurement;
				count1+=mpkt0->count;}

			}else{
				atomic{
				aggregate_measurement2+=mpkt0->measurement;
				count2+=mpkt0->count;}

			}			
			//if message has 2 groups of nodes	
		}else if(len == sizeof(MeasurementMsg1)){
			mpkt1 = (MeasurementMsg1*) (call MeasurementPacket.getPayload(&radioMeasurementRecPkt,len));	
			dbg("final","received group1\n");	
			
			atomic{//decode includedGroups to find out the included group
			//and add measurements to local variables
			receiveIncludedGroups=mpkt1->includedGroups;}
			//if group 0 and 1 exist
			if((receiveIncludedGroups & 0b11) == 0b11){
				atomic{
				aggregate_measurement+=mpkt1->measurement;
				count+=mpkt1->count;
				aggregate_measurement1+=mpkt1->measurement1;
				count1+=mpkt1->count1;}
			}else if((receiveIncludedGroups & 0b01) == 0b01){ //group 0 and 2
			atomic{
				aggregate_measurement+=mpkt1->measurement;
				count+=mpkt1->count;
				aggregate_measurement2+=mpkt1->measurement1;
				count2+=mpkt1->count1;}
			}else{ //1 and 2 
			atomic{
				aggregate_measurement1+=mpkt1->measurement;
				count1+=mpkt1->count;
				aggregate_measurement2+=mpkt1->measurement1;
				count2+=mpkt1->count1;}

			}
			
		//if message has 3 groups of nodes	
		}else if(len == sizeof(MeasurementMsg2)){
			mpkt2 = (MeasurementMsg2*) (call MeasurementPacket.getPayload(&radioMeasurementRecPkt,len));	
			dbg("final","received group2\n");			
			atomic{
			receiveIncludedGroups=mpkt2->includedGroups;
			aggregate_measurement+=mpkt2->measurement;
			count+=mpkt2->count;
			aggregate_measurement1+=mpkt2->measurement1;
			count1+=mpkt2->count1;
			aggregate_measurement2+=mpkt2->measurement2;
			count2+=mpkt2->count2;}
		}
		else
		{
			dbg("comm","receiveMeasurementTask():Empty message!!! \n");
#ifdef PRINTFDBG_MODE
			printf("receiveMeasurementTask():Empty message!!! \n");
			printfflush();
#endif
			setLostMeasurementRecTask(TRUE);
			return;
		}
		

	}
	
	task void receiveRoutingTask()
	{
		message_t tmp;
		uint8_t len;
		message_t radioRoutingRecPkt;
		
#ifdef PRINTFDBG_MODE
		printf("ReceiveRoutingTask():received msg...\n");
		printfflush();
#endif
		radioRoutingRecPkt= call RoutingReceiveQueue.dequeue();
		
		len= call RoutingPacket.payloadLength(&radioRoutingRecPkt);
		
		dbg("SRTreeC","ReceiveRoutingTask(): len=%u \n",len);
#ifdef PRINTFDBG_MODE
		printf("ReceiveRoutingTask(): len=%u!\n",len);
		printfflush();
#endif
		// processing of routing packet			
		if(len == sizeof(RoutingMsg))
		{			
			RoutingMsg * mpkt = (RoutingMsg*) (call RoutingPacket.getPayload(&radioRoutingRecPkt,len));		
			
			dbg("SRTreeC" , "receiveRoutingTask():senderID= %d , depth= %d \n", mpkt->senderID , mpkt->depth);
#ifdef PRINTFDBG_MODE
			printf("NodeID= %d , RoutingMsg received! \n",TOS_NODE_ID);
			printf("receiveRoutingTask():senderID= %d , depth= %d \n", mpkt->senderID , mpkt->depth);
			printfflush();
#endif		//if node doesnt have father yet
			if ( (parentID<0)||(parentID>=65535))
			{
				// set the message sender as father
				parentID= call RoutingAMPacket.source(&radioRoutingRecPkt);//mpkt->senderID;q
				//depth += father depth
				curdepth= mpkt->depth + 1;
				//set group accoring to the RANDOM_NUM received down from base node
				RANDOM_NUM=mpkt->RANDOM_NUM;
				group=TOS_NODE_ID%RANDOM_NUM;

				dbg("RoutingMsg","NodeID= %d : curdepth= %d , parentID= %d \n", TOS_NODE_ID ,curdepth , parentID);
				
				//broadcast that youre available for parenting
				if (TOS_NODE_ID!=0)
				{
					call RoutingMsgTimer.startOneShot(TIMER_FAST_PERIOD);
				}
			}
			
		}
		else
		{
			dbg("SRTreeC","receiveRoutingTask():Empty message!!! \n");
#ifdef PRINTFDBG_MODE
			printf("receiveRoutingTask():Empty message!!! \n");
			printfflush();
#endif
			setLostRoutingRecTask(TRUE);
			return;
		}
		
	}


	
	
	 
	
	
}
