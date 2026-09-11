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
    <title>Easeculator</title>
    <meta charset="UTF-8" />
    <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/bootstrap-icons@1.11.3/font/bootstrap-icons.min.css">
    <style>
        :root {
            --primary-color: #000000; /* Blue for buttons and accents */
            --secondary-color: #ffffff; /* White for text on buttons */
            --text-color: #000000; /* Black for general text */
            --accent-color: #f5f5f5;
            --error-color: #e74c3c;
            --success-color: #2ecc71;
            --background-color: #f0f2f5;
            --tooltip-bg: #333333;
            --button-hover: #357ab8;
            --input-border: #cccccc;
            --border-radius: 8px;
            --transition-speed: 0.3s;
        }

        * {
            box-sizing: border-box;
            margin: 0;
            padding: 0;
        }

        body {
            font-family: "Roboto", sans-serif;
            background-color: var(--background-color);
            display: flex;
            align-items: center;
            justify-content: center;
            min-height: 100vh;
            padding: 20px;
        }

        #app {
            width: 100%;
            max-width: 600px;
            background-color: var(--secondary-color);
            border-radius: var(--border-radius);
            box-shadow: 0 4px 6px rgba(0, 0, 0, 0.1);
            padding: 2rem;
            position: relative;
        }

        #app h1 {
            text-align: center;
            margin-bottom: 1.5rem;
            color: var(--text-color);
            font-size: 2rem;
        }

        form label {
            position: relative;
            display: block;
            margin-bottom: 1.5rem;
        }

        label span {
            color: var(--text-color);
            font-weight: 500;
            display: block;
            margin-bottom: 0.5rem;
        }

        label p {
            display: flex;
            align-items: center;
            gap: 0.4rem;
            margin-bottom: 0.5rem;
            color: var(--text-color);
        }

        input,
        select {
            width: 100%;
            padding: 0.75rem 1rem;
            margin: 0;
            border: 1px solid var(--input-border);
            border-radius: var(--border-radius);
            font-size: 1rem;
            transition: border-color var(--transition-speed), box-shadow var(--transition-speed);
        }

        input:focus,
        select:focus {
            border-color: var(--primary-color);
            box-shadow: 0 0 5px rgba(74, 144, 226, 0.5);
            outline: none;
        }

        .tax-year select {
            width: 100%;
        }

        .error-icon-container {
            position: absolute;
            right: 10px;
            top: 50%;
            transform: translateY(-50%);
            color: var(--error-color);
            display: none;
        }

        label input.invalid,
        label select.invalid {
            border-color: var(--error-color);
        }

        label input.invalid + .error-icon-container,
        label select.invalid + .error-icon-container {
            display: block;
        }

        .select-label {
            margin-bottom: 0.5rem;
        }

        .deductions-label {
            margin-top: 0.5rem;
        }

        .bi-exclamation-circle {
            cursor: pointer;
        }

        .bi-question-circle {
            cursor: pointer;
            color: var(--text-color);
        }

        .tooltip {
            position: relative;
            display: inline-block;
        }

        .tooltip .tooltiptext {
            visibility: hidden;
            width: 200px;
            background-color: var(--tooltip-bg);
            color: var(--secondary-color);
            text-align: center;
            border-radius: var(--border-radius);
            padding: 8px;
            position: absolute;
            z-index: 1;
            bottom: 125%;
            left: 50%;
            transform: translateX(-50%);
            opacity: 0;
            transition: opacity var(--transition-speed);
            font-size: 0.875rem;
        }

        .tooltip .tooltiptext::after {
            content: "";
            position: absolute;
            top: 100%;
            left: 50%;
            margin-left: -5px;
            border-width: 5px;
            border-style: solid;
            border-color: var(--tooltip-bg) transparent transparent transparent;
        }

        .tooltip:hover .tooltiptext {
            visibility: visible;
            opacity: 1;
        }

        .submit {
            width: 100%;
            background: var(--primary-color);
            border: none;
            color: var(--secondary-color);
            padding: 0.75rem;
            border-radius: var(--border-radius);
            margin-top: 1rem;
            cursor: pointer;
            font-size: 1rem;
            transition: background-color var(--transition-speed);
        }

        .submit:hover {
            background-color: var(--button-hover);
        }

        #result {
            z-index: 2;
            position: fixed;
            top: 50%;
            left: 50%;
            transform: translate(-50%, -50%);
            background: var(--secondary-color);
            width: 90%;
            max-width: 500px;
            border-radius: var(--border-radius);
            box-shadow: 0 4px 6px rgba(0, 0, 0, 0.1);
            padding: 2rem;
            display: none;
            flex-direction: column;
            align-items: center;
            justify-content: center;
            color: var(--text-color);
            animation: fadeIn 0.5s ease-in-out;
        }

        #result h2 {
            margin-bottom: 0.5rem;
            color: var(--primary-color);
        }

        #result h3 {
            margin-bottom: 1rem;
            font-size: 1.5rem;
            color: var(--text-color);
        }

        #result h4 {
            margin-bottom: 1.5rem;
            font-size: 1.25rem;
        }

        .close {
            width: 100%;
            background: var(--error-color);
            border: none;
            color: var(--secondary-color);
            padding: 0.75rem;
            border-radius: var(--border-radius);
            cursor: pointer;
            font-size: 1rem;
            transition: background-color var(--transition-speed);
        }

        .close:hover {
            background-color: #c0392b; /* Darker shade of error color */
        }

        @keyframes fadeIn {
            from { opacity: 0; transform: translate(-50%, -60%); }
            to { opacity: 1; transform: translate(-50%, -50%); }
        }

        /* Responsive Design */
        @media (max-width: 600px) {
            #app {
                padding: 1.5rem;
            }

            #app h1 {
                font-size: 1.5rem;
            }

            .tooltip .tooltiptext {
                width: 150px;
            }
        }
    </style>
</head>
<body>
    <div id="app">
        <h1>Easeculator</h1>
        <form id="tax-form" onsubmit="event.preventDefault(); calculateTax();">
            <label>
                <span><b>Enter Year:</b></span>
                <div class="tax-year">
                    <select id="tax-year" required>
                        <option value="" disabled selected hidden>Select year</option>
                        <option value="2024">2024</option>
                        <option value="2023">2023</option>
                        <option value="2022">2022</option>
                        <option value="2021">2021</option>
                    </select>
                </div>
            </label>

            <label>
                <span><b>Enter Gross Annual Income</b></span>
                <div style="position: relative;">
                    <input 
                        type="number" 
                        placeholder="Enter gross annual income" 
                        value="<?php echo isset($user_data['incomestatus']) ? $user_data['incomestatus'] : '';?>" 
                        id="gross-income" 
                        required 
                        min="0"
                    />
                    <i class="bi bi-exclamation-circle error-icon-container tooltip" id="error-icon-gross-income">
                        <span class="tooltiptext">Please enter numbers only</span>
                    </i>
                </div>
                <span class="bi bi-question-circle tooltip">
                    <span class="tooltiptext">Gross annual income is your total salary in a year before any deductions</span>
                </span>
            </label>

            <label>
                <span><b>Enter Extra Income</b></span>
                <div style="position: relative;">
                    <input 
                        type="number" 
                        placeholder="Enter extra income from other sources" 
                        id="extra-income" 
                        min="0"
                    />
                    <i class="bi bi-exclamation-circle error-icon-container tooltip" id="error-icon-extra-income">
                        <span class="tooltiptext">Please enter numbers only</span>
                    </i>
                </div>
                <span class="bi bi-question-circle tooltip">
                    <span class="tooltiptext">Extra income is your income from other sources excluding gross income</span>
                </span>
            </label>

            <label>
                <span class="select-label"><b>Enter Age Group</b></span>
                <span class="bi bi-question-circle tooltip">
                    <span class="tooltiptext">Select your age from given age group options</span>
                </span>
                <div id="select-container" style="position: relative;">
                    <select id="age-group" required>
                        <option value="" disabled selected hidden>Select age group</option>
                        <option value="lessthan40">Less than 40</option>
                        <option value="between40and60">40 - 60</option>
                        <option value="greaterthan60">Above 60</option>
                    </select>
                    <i class="bi bi-exclamation-circle error-icon-container tooltip" id="error-icon-age-group">
                        <span class="tooltiptext">Please select an age group</span>
                    </i>
                </div>
            </label>

            <label>
                <span class="deductions-label"><b>Enter Total Applicable Deductions</b></span>
                <div style="position: relative;">
                    <input 
                        type="number" 
                        placeholder="Add total applicable deductions" 
                        id="total-deductions" 
                        min="0"
                    />
                    <i class="bi bi-exclamation-circle error-icon-container tooltip" id="error-icon-total-deductions">
                        <span class="tooltiptext">Please enter numbers only</span>
                    </i>
                </div>
                <span class="bi bi-question-circle tooltip">
                    <span class="tooltiptext">Enter total applicable deductions for gross and extra income</span>
                </span>
            </label>

            <button type="submit" class="submit">Calculate Tax</button>
        </form>

        <div id="result">
            <h2>Your Overall Income Will Be</h2>
            <h3 id="overall-income">0.00</h3>
            <h5 id="tax-text">after tax deductions</h5>
            <h4>Tax Amount: <span id="tax-amount">0.00</span></h4>
            <button class="close" onclick="closeResult()">Close</button>
        </div>
    </div>

    <script>
        function calculateTax() {
            // Retrieve input values
            const grossIncome = parseFloat(document.getElementById("gross-income").value) || 0;
            const extraIncome = parseFloat(document.getElementById("extra-income").value) || 0;
            const ageGroup = document.getElementById("age-group").value;
            const deductions = parseFloat(document.getElementById("total-deductions").value) || 0;

            // Output the values to console for debugging
            console.log('Gross Income:', grossIncome);
            console.log('Extra Income:', extraIncome);
            console.log('Age Group:', ageGroup);
            console.log('Deductions:', deductions);

            // Form validation
            let isValid = true;

            // Validate Gross Income
            const grossIncomeInput = document.getElementById("gross-income");
            if (grossIncome < 0 || isNaN(grossIncome)) {
                grossIncomeInput.classList.add("invalid");
                isValid = false;
            } else {
                grossIncomeInput.classList.remove("invalid");
            }

            // Validate Extra Income
            const extraIncomeInput = document.getElementById("extra-income");
            if (extraIncome < 0 || isNaN(extraIncome)) {
                extraIncomeInput.classList.add("invalid");
                isValid = false;
            } else {
                extraIncomeInput.classList.remove("invalid");
            }

            // Validate Age Group
            const ageGroupSelect = document.getElementById("age-group");
            if (!ageGroup) {
                ageGroupSelect.classList.add("invalid");
                isValid = false;
            } else {
                ageGroupSelect.classList.remove("invalid");
            }

            // Validate Deductions
            const deductionsInput = document.getElementById("total-deductions");
            if (deductions < 0 || isNaN(deductions)) {
                deductionsInput.classList.add("invalid");
                isValid = false;
            } else {
                deductionsInput.classList.remove("invalid");
            }

            if (!isValid) {
                alert("Please correct the highlighted fields.");
                return;
            }

            // Calculate total income
            const totalIncome = grossIncome + extraIncome;
            let taxFreeLimit = 0; // Default tax-free limit

            // Adjust tax-free limit based on age group
            if (ageGroup === "greaterthan60") {
                taxFreeLimit = 400000;
            } else if (ageGroup === "between40and60" || ageGroup === "lessthan40") {
                taxFreeLimit = 350000;
            }

            // Subtract deductions from total income
            let taxableIncome = totalIncome - deductions;
            console.log('Taxable Income Before Limit:', taxableIncome);

            // Apply the tax-free limit
            if (taxableIncome <= taxFreeLimit) {
                document.getElementById("overall-income").innerText = totalIncome.toFixed(2);
                document.getElementById("tax-amount").innerText = "0.00";
                document.getElementById("result").style.display = "flex";
                return;
            }

            taxableIncome -= taxFreeLimit;
            console.log('Taxable Income After Limit:', taxableIncome);

            let tax = 0;

            // Apply tax brackets based on remaining taxable income
            if (taxableIncome > 0 && taxableIncome <= 100000) {
                tax = taxableIncome * 0.05;
            } else if (taxableIncome > 100000 && taxableIncome <= 500000) {
                tax = (taxableIncome - 100000) * 0.10 + 100000 * 0.05;
            } else if (taxableIncome > 500000 && taxableIncome <= 1000000) {
                tax = (taxableIncome - 500000) * 0.15 + 400000 * 0.10 + 100000 * 0.05;
            } else if (taxableIncome > 1000000 && taxableIncome <= 1500000) {
                tax = (taxableIncome - 1000000) * 0.25 + 500000 * 0.15 + 400000 * 0.10 + 100000 * 0.05;
            } else if (taxableIncome > 1500000) {
                tax = (taxableIncome - 1500000) * 0.30 + 500000 * 0.25 + 500000 * 0.15 + 400000 * 0.10 + 100000 * 0.05;
            }

            console.log('Calculated Tax:', tax);

            // Final income after tax
            const finalIncome = totalIncome - tax;
            console.log('Final Income After Tax:', finalIncome);

            // Display the results: final income and tax amount
            document.getElementById("overall-income").innerText = finalIncome.toFixed(2);
            document.getElementById("tax-amount").innerText = tax.toFixed(2);
            document.getElementById("result").style.display = "flex";
        }

        function closeResult() {
            document.getElementById("result").style.display = "none";
        }
    </script>
</body>
</html>
