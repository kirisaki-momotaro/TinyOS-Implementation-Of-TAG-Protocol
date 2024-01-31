#include "SimpleRoutingTree.h"

configuration SRTreeAppC @safe() { }
implementation{
	components SRTreeC;

#if defined(DELUGE) //defined(DELUGE_BASESTATION) || defined(DELUGE_LIGHT_BASESTATION)
	components DelugeC;
#endif

#ifdef PRINTFDBG_MODE
		components PrintfC;
#endif
	components MainC, ActiveMessageC, RandomC, RandomMlcgC; // Added RandomC and RandomMlcgC. 	
	components new TimerMilliC() as RoutingMsgTimerC;
	components new TimerMilliC() as LostTaskTimerC;
	//timer for data transmition
	components new TimerMilliC() as SendMeasurementTimerC;
	//routing done event timer
	components new TimerMilliC() as RoutingFinishedTimerC;

	
	components new AMSenderC(AM_ROUTINGMSG) as RoutingSenderC;
	components new AMReceiverC(AM_ROUTINGMSG) as RoutingReceiverC;

	// New components for measurements.
	// xreiazetai allagh to am routing msg i guess
	components new AMSenderC(AM_MEASUREMENTMSG) as MeasurementSenderC;
	components new AMReceiverC(AM_MEASUREMENTMSG) as MeasurementReceiverC;
	
	components new PacketQueueC(SENDER_QUEUE_SIZE) as RoutingSendQueueC;
	components new PacketQueueC(RECEIVER_QUEUE_SIZE) as RoutingReceiveQueueC;

	// New components for measurement queues. 
	components new PacketQueueC(SENDER_QUEUE_SIZE) as MeasurementSendQueueC;
	components new PacketQueueC(RECEIVER_QUEUE_SIZE) as MeasurementReceiveQueueC;
	
	SRTreeC.Boot->MainC.Boot;
	
	SRTreeC.RadioControl -> ActiveMessageC;
	
	SRTreeC.RoutingMsgTimer->RoutingMsgTimerC;
	SRTreeC.LostTaskTimer->LostTaskTimerC;
	//wire message timer
	SRTreeC.SendMeasurementTimer->SendMeasurementTimerC;
	//wire rooting timer
	SRTreeC.RoutingFinishedTimer->RoutingFinishedTimerC;

	SRTreeC.RoutingPacket->RoutingSenderC.Packet;
	SRTreeC.RoutingAMPacket->RoutingSenderC.AMPacket;
	SRTreeC.RoutingAMSend->RoutingSenderC.AMSend;
	SRTreeC.RoutingReceive->RoutingReceiverC.Receive;
	
	// New wirings for measurement purposes added.
	SRTreeC.MeasurementPacket->MeasurementSenderC.Packet;
	SRTreeC.MeasurementAMPacket->MeasurementSenderC.AMPacket;
	SRTreeC.MeasurementAMSend->MeasurementSenderC.AMSend;
	SRTreeC.MeasurementReceive->MeasurementReceiverC.Receive;
	
	SRTreeC.RoutingSendQueue->RoutingSendQueueC;
	SRTreeC.RoutingReceiveQueue->RoutingReceiveQueueC;

	// New wirings for measurement queues added.
	SRTreeC.MeasurementSendQueue->MeasurementSendQueueC;
	SRTreeC.MeasurementReceiveQueue->MeasurementReceiveQueueC;
	
	// Used for random number creation
	SRTreeC.RandomMeasurement->RandomC;
	SRTreeC.Seed->RandomMlcgC.SeedInit;
	
}
