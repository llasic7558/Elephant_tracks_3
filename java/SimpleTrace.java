// Simple test program for Elephant Tracks tracing
class SimpleTrace {
    static class Node {
        int value;
        Node next;
        
        Node(int val) {
            this.value = val;
            this.next = null;
        }
    }
    
    public static void main(String[] args) {
        System.out.println("Starting SimpleTrace test...");
        
        // Create a simple linked list
        Node head = new Node(1);
        Node current = head;
        
        for (int i = 2; i <= 10; i++) {
            current.next = new Node(i);
            current = current.next;
        }
        
        // Traverse and print the list
        System.out.print("List values: ");
        current = head;
        while (current != null) {
            System.out.print(current.value + " ");
            current = current.next;
        }
        System.out.println();
        
        // Create some more allocations
        String[] strings = new String[5];
        for (int i = 0; i < strings.length; i++) {
            strings[i] = "String " + i;
        }
        
        System.out.println("Test completed successfully!");
    }
}
