<?php
include('connect.php'); 
session_start();

// Check if user is logged in
if (!isset($_SESSION['user_id'])) {
    header("Location: login.php");
    exit();
}

// Get the user ID from the session
$user_id = $_SESSION['user_id'];

// Fetch user details from the database
$query = "SELECT incomestatus FROM registered WHERE user_id = '$user_id'";
$result = mysqli_query($conn, $query);

if ($result && mysqli_num_rows($result) > 0) {
    $user_data = mysqli_fetch_assoc($result);
} else {
    echo "<script>alert('User data not found.');</script>";
}
?>
<!DOCTYPE html>
<html>
  <head>
    <title>Business Tax Calculator</title>
    <meta charset="UTF-8" />
    <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/bootstrap-icons@1.11.3/font/bootstrap-icons.min.css">
    <style>
      <style type="text/css">
 
 :root {
   --outline-color: #c6c0db;
   --label-color: #394852;
   --input-border: #767676;
   --tooltiptext-background: #4c5d6b;
   --text-color: white;
   --button-bg: #000000;
   --black: black;
 }
 
 * {
   box-sizing: border-box;
   margin: 0;
   padding: 0;
 }
 
 body {
   font-family: "Roboto", sans-serif;
   display: flex;
   height: 100svh;
   align-items: center;
   justify-content: center;
 }
 
 #app {
   width: 600px;
   border: 5px solid var(--tooltiptext-background);
   padding: 2rem;
   position: relative;
 }
 
 #app h1 {
   text-align: center;
   margin-bottom: 0.8rem;
 }
 
 label {
   position: relative;
 }
 
 label span {
   color: var(--label-color);
   font-weight: 500;
 }
 
 label p {
   display: flex;
   align-items: center;
   gap: 0.4rem;
 }
 
 input,
 select {
   width: 100%;
   padding: 0.5rem;
   margin: 0.2rem 0 0.7rem 0;
 }
 
 select {
   width: 90%;
   border-right: 0px;
 }
 
 .error-icon-container {
   border: 1px solid var(--input-border);
   border-left: 0;
   width: 10%;
   height: 2.2rem;
   position: relative;
   top: 0px;
 }
 
 #select-container {
   display: flex;
 }
 
 #select-container select {
   margin: 0;
 }
 
 #age-group:focus {
   outline: none;
 }
 
 #select-container:focus-within {
   outline: 2px solid var(--black);
 }
 
 .select-label {
   margin-bottom: 0.2rem;
 }
 
 .deductions-label {
   margin-top: 0.7rem;
 }
 
 label .bi-exclamation-circle {
   position: absolute;
   cursor: pointer;
   display: none;
 }
 
 label #error-icon-gross-income {
   right: 4%;
   top: 65%;
 }
 
 #error-icon-extra-income {
   right: 11px;
   top: 80%;
 }
 
 #error-icon-age-group {
   right: 11px;
   top: 25%;
 }
 
 #error-icon-total-deductions {
   top: 33%;
   right: -282px;
 }
 
 label .bi-question-circle {
   cursor: pointer;
 }
 
 .tooltip {
   position: relative;
 }
 
 .tooltip .tooltiptext {
   visibility: hidden;
   width: 125px;
   background-color: var(--tooltiptext-background);
   color: var(--text-color);
   border-radius: 6px;
   padding: 5px 0;
   position: absolute;
   z-index: 1;
   bottom: 140%;
   left: 50%;
   margin-left: -15px;
   opacity: 0;
   transition: opacity 0.3s;
   padding: 10px;
   font-size: 12px;
 }
 
 .tooltip .tooltiptext::after {
   content: "";
   position: absolute;
   top: 100%;
   left: 10%;
   margin-left: -5px;
   border-width: 5px;
   border-style: solid;
   border-color: var(--tooltiptext-background) transparent transparent
     transparent;
 }
 
 .tooltip:hover .tooltiptext {
   visibility: visible;
   opacity: 1;
 }
 
 .submit {
   width: 100%;
 }
 
 .close {
   width: 18%;
 }
 
 .submit,
 .close {
   background: var(--button-bg);
   border: none;
   color: var(--text-color);
   padding: 0.5rem;
   border-radius: 5px;
   margin-top: 1.5rem;
   cursor: pointer;
 }
 
 h2 {
   margin-bottom: 0.2rem;
 }
 
 #result {
   z-index: 2;
   position: absolute;
   top: 7%;
   left: -30px;
   background: var(--text-color);
   width: 420px;
   border: 1px solid var(--outline-color);
   padding: 1.5rem;
   height: 380px;
   display: flex;
   align-items: center;
   justify-content: center;
   flex-direction: column;
   color: var(--label-color);
   display: none;
 }
 
 </style>
    </style>
  </head>
  <body>
    <div id="app">
      <h1>Business Tax Calculator</h1>
      <label>
        <p><span><b>Select Fiscal Year:</b></span></p>
        <select id="fiscal-year">
          <option value="">2024</option>
          <option value="">2023</option>
          <option value="">2022</option>
          <option value="">2021</option>
        </select>
      </label>
      
      <label>
        <p><span><b>Enter Gross Revenue</b></span></p>
        <input placeholder="Enter gross revenue" id="gross-revenue" />
      </label>

      <label>
        <p><span><b>Enter Total Expenses</b></span></p>
        <input placeholder="Enter total expenses" id="total-expenses" />
      </label>

      <label>
        <p><span><b>Enter Total Deductions</b></span></p>
        <input placeholder="Enter total deductions" id="total-deductions" />
      </label>

      <button class="submit" onclick="calculateBusinessTax()">Calculate Tax</button>

      <div id="result">
        <h2>Net Profit: <span id="net-profit">0</span></h2>
        <h4>Corporate Tax Amount: <span id="tax-amount">0</span></h4>
        <button class="close" onclick="closeResult()">Close</button>
      </div>
    </div>

    <script>
      function calculateBusinessTax() {
        // Retrieve input values
        const grossRevenue = parseFloat(document.getElementById("gross-revenue").value) || 0;
        const totalExpenses = parseFloat(document.getElementById("total-expenses").value) || 0;
        const deductions = parseFloat(document.getElementById("total-deductions").value) || 0;

        // Calculate Net Profit
        let netProfit = grossRevenue - totalExpenses - deductions;
        console.log('Net Profit:', netProfit);

        // Minimum tax of 0.6% of gross revenue if the company makes a loss or minimal profit
        let minimumTax = grossRevenue * 0.006;
        
        // Standard corporate tax rate of 27.5% for profits
        let corporateTaxRate = 0.275;
        let taxAmount = 0;

        if (netProfit > 0) {
          // Apply corporate tax rate on profit
          taxAmount = netProfit * corporateTaxRate;
          if (taxAmount < minimumTax) {
            taxAmount = minimumTax; // Ensure minimum tax is paid
          }
        } else {
          // Apply minimum tax when in loss
          taxAmount = minimumTax;
        }

        // Display the results
        document.getElementById("net-profit").innerText = netProfit.toFixed(2);
        document.getElementById("tax-amount").innerText = taxAmount.toFixed(2);
        document.getElementById("result").style.display = "flex";
      }

      function closeResult() {
        document.getElementById("result").style.display = "none";
      }
    </script>
  </body>
</html>
